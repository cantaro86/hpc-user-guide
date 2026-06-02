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

## Example: install and use fmt

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