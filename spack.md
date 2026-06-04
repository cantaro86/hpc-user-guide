# Spack guide


## Local spack settings

Users can install software with the centrally provided Spack without needing root privileges, as long as new builds, caches, and bootstrap files are written in the user’s home directory instead of the shared system tree.    
The shared Spack packages can remain read-only in  `/cm/shared/apps/spack-packages`, while user-installed software goes under `~/.spack`.   
A practical setup is to keep the system Spack executable at  `/cm/shared/apps/spack/bin/spack`, point the user install tree to  `~/.spack/opt/spack`, and chain the shared installation as an upstream so already installed cluster packages can be reused. This avoids rebuilding common packages such as compilers, MPI stacks, or libraries that are already present in the central installation.

Use the following one-time configuration in the user’s home directory:

```bash
mkdir -p ~/.spack

cat > ~/.spack/config.yaml << 'EOF'
config:
  install_tree:
    root: ~/.spack/opt/spack
  build_stage: ~/.spack/build_stage
  source_cache: ~/.spack/cache
  bootstrap:
  root: ~/.spack/bootstrap
EOF

cat > ~/.spack/upstreams.yaml << 'EOF'
upstreams:
  system-spack:
    install_tree: /cm/shared/apps/spack-packages
    modules:
      tcl: /cm/shared/modulefiles
EOF
```


This configuration keeps user builds local and lets Spack search the shared package tree first when resolving dependencies. Setting a user-local bootstrap root is important because otherwise Spack may try to write bootstrap files into the central Spack installation, which regular users cannot modify.


```bash

module load spack

# add gcc-14 to ~/.spack/packages.yaml 
spack compiler find /cm/shared/apps/gcc-14

# we can see the compilers with
spack compilers
```

## Example: install and use the C++ library fmt

After the files are in place, users can test the setup with:

```bash
module load spack/1.0
spack find
spack info fmt
spack spec fmt
```

If the setup is correct, `spack find` should list shared packages, and any new install should be placed in `~/.spack/opt/spack`.    
To install it locally use

```bash
spack install fmt %gcc@14.2.0
```
After installation you can load it with 

```bash
spack load fmt
```

Create a test program `hello_fmt.cpp`:
```c++
#include <fmt/core.h>

int main() {
    fmt::print("Hello, {}!\n", "cluster");
    fmt::print("The answer is {}\n", 42);
    return 0;
}
```
And compile it with
```bash
module load gcc/14.2.0

# compile the c++ program
g++ -o hello_fmt hello_fmt.cpp $(pkg-config --cflags --libs fmt)

# equivalent to 
FMT_PREFIX=$(spack location -i fmt)
g++ -o hello_fmt hello_fmt.cpp \
    -I${FMT_PREFIX}/include \
    -L${FMT_PREFIX}/lib \
    -lfmt

./hello_fmt
```
Using  `pkg-config --cflags --libs fmt` is convenient because it injects the correct include and library flags for the installed  fmt  package without requiring users to manually discover the installation prefix. 

The expected output is:
```
Hello, cluster!
The answer is 42
```
---------------------------------------------------

The command `spack load <package>` sets some environment variables.
you can see them with
```bash
spack load --sh fmt   # Shows all env vars it would set
```


## Spack environments

 Spack environments are similar to virtual environments in other package managers (e.g., Python venv, Conda Environments).


 # Local package installation (advanced C++ example)

Let us create a small C++ project in the folder `~/spack_tests/dev-source`:   
It contains these files:

```c++
// hello_openmp.cpp
#include <fmt/core.h>
#include <omp.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
#pragma omp parallel num_threads(4)
    {
        fmt::print("Hello World... from thread = {} of total {} threads\n", omp_get_thread_num(),
               omp_get_num_threads());
    }
    return 0;
}
```
and
```cmake
cmake_minimum_required(VERSION 3.22)

project(hello_openmp LANGUAGES CXX)


if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
    set(CMAKE_INSTALL_PREFIX "$ENV{HOME}/.local" CACHE PATH "Install prefix" FORCE)
endif()
 
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(CMAKE_CONFIGURATION_TYPES Debug Release CI CACHE STRING "Choose the type of build." FORCE)
set(CMAKE_CXX_FLAGS_CI "-O2 -g -Wall -Wextra -Wpedantic -Werror -fsanitize=address,undefined")
set(CMAKE_C_FLAGS_CI "-O2 -g -Wall -Wextra -Wpedantic -Werror -fsanitize=address,undefined")

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE CI CACHE STRING "Build type" FORCE)
endif()

message(STATUS "C++ compiler: ${CMAKE_CXX_COMPILER}")
message(STATUS "Compiler ID: ${CMAKE_CXX_COMPILER_ID}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Generator: ${CMAKE_GENERATOR}")

add_executable(${PROJECT_NAME} hello_openmp.cpp)

find_package(OpenMP REQUIRED)
find_package(fmt CONFIG REQUIRED)

target_link_libraries(${PROJECT_NAME}
    PRIVATE
        OpenMP::OpenMP_CXX
        fmt::fmt
)

# Installation rules
include(GNUInstallDirs)

install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
```

### Create a spack repo

```bash
# Create and register repo
mkdir -p ~/.spack/package_repos/myrepo/packages/hello-openmp
cat > ~/.spack/package_repos/myrepo/repo.yaml <<'EOF'
repo:
  namespace: myrepo
EOF
spack repo add ~/.spack/package_repos/myrepo
```

The file `~/.spack/package_repos/myrepo/packages/hello-openmp/package.py` contains this:
```python
from spack.package import *

class HelloOpenmp(CMakePackage):
    """A simple Hello World OpenMP example with fmt library"""

    homepage = "https://github.com/yourusername/hello_openmp"
    version("main")

    # Build dependencies
    depends_on("cmake@4.1.1:", type="build")
    depends_on("ninja", type="build")

    # Runtime dependencies
    depends_on("fmt")

    def cmake_args(self):
        """Configure CMake arguments"""
        return [
            self.define("CMAKE_CXX_STANDARD", "20"),
        ]
```
For a Spack package named `hello-openmp`, Spack expects the class name to match the package name converted to CamelCase. In practice, `hello-openmp` maps to `HelloOpenmp`.

We can see the repo and some details with 
```bash
spack repo list
spack info hello-openmp
```

### Create a spack independent env

```bash
# Create environment
mkdir -p ~/spack_tests/hello-env
cd ~/spack_tests/hello-env
spack env create -d .
spack env activate .
```

You can check that the independent environment is active with:
```bash
echo $SPACK_ENV
```

After activation, register compilers

```bash
spack compiler find
spack compiler list
```

Add your package and mark it as a development source tree:

```bash
# Add package and point to local sources
spack add hello-openmp@main %gcc
spack develop --path ~/spack_tests/dev-source hello-openmp@main
spack concretize -f
```

You can see the concretized package with 
```bash
spack find -c
```

Spack develop only works in an active environment.   
After that we can build the project:
```bash
cd ~/spack_tests/dev-source
spack dev-build hello-openmp@main
```

### Run the installed package

The program was installed in the folder:

```bash
spack location -i hello-openmp@main
```

We can load and run the program with:
```bash
spack load hello-openmp
hello_openmp
```

### Enter the build environment

Sometimes it may be helpful to enter the build environment
```bash
spack build-env hello-openmp@main bash --norc
```


### Uninstall

```bash
spack find -lv hello-openmp@main

spack uninstall hello-openmp@main
# or
spack uninstall /<hash>
```

The build directory can be deleted manually

```bash
rm -rf ~/spack_tests/dev-source/build-linux-ubuntu22.04-cascadelake-66svhxl/
``` 


### Rebuild

If modifications are made in the package.py file, you need to reconcretize the environment: 

```bash
# Uninstall first
spack uninstall hello-openmp@main

# Remove and re-add spec
spack remove hello-openmp@main
spack add hello-openmp@main %gcc@14.2.0

# Reconcretize
spack concretize -f
```

```bash
# Clean the build folder
spack clean hello-openmp
spack dev-build hello-openmp@main
```



###  Extra 

If you want to change generator and build type:

```bash
# Remove old installation
spack uninstall hello-openmp@main

# Add with new variants
spack add hello-openmp@main generator=ninja build_type=Debug

# Rebuild
spack concretize -f
spack install hello-openmp@main
``` 