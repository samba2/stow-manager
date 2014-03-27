## Introduction

This is a working prototype of an application level based package manager
based on GNU stow (www.gnu.org/software/stow/)

*stow* installs a specific version of a program from the so called *stow dir*
to a destination directory. 

The intent of this prototype was to find out if adding missing functionality to
the core *stow* application (like repository support) would be a simple
replacement for non-root installations of software on a Linux system.

If *stow* is a very simplified *dpkg*, then *stow-manager* is a very simplified 
(and dumb) version of *apt-get*.
## Overview

The following picture describes the whole idea of the stow manager:

     +--------------------------------------------+
     |          REPOSITORY AT WEB-SERVER          |
     +--------------------------------------------+
     | /packages/prog1_4.2.1.tar.gz               |
     |           prog1_4.2.2.tar.gz               |
     |           prog2_3.2.4.tar.gz               |
     |           prog2_3.4.2.tar.gz               |
     |                                            |
     | /releases/firstRelease/prog1_4.2.1.tar.gz  |
     |                        prog2_3.2.4.tar.gz  |
     |                                            |
     |          /secondRelease/prog1_4.2.2.tar.gz |
     |                         prog2_3.4.2.tar.gz |
     +--------------------+-----------------------+
                          |
                          | download and extract
                          |
     +---------------------------------------------+
     |                    |       MY COMPUTER      |
     +---------------------------------------------+
     |                    |                        |
     |                    v                        |
     |      +----------------------------+         |
     |      |        STAGING AREA        |         |
     |      +----------------------------+         |
     |      |  /staging/prog1_4.2.1/dir1 |         |
     |      |                       dir2 |         |
     |      |                            |         |
     |      |          /prog2_3.2.4/dir3 |         |
     |      |                       dir4 |         |
     |      +-------------+--------------+         |
     |                    |                        |
     |                    |  "stow"                |
     |                    |  (install via symlinks)|
     |                    v                        |
     |            +----------------+               |
     |            | ROOT DIRECTORY |               |
     |            +----------------+               |
     |            | /my_progs/dir1 |               |
     |            |           dir2 |               |
     |            |           dir3 |               |
     |            |           dir4 |               |
     |            +----------------+               |
     +---------------------------------------------+

## Repository Layout

There is directory on a web server which contains the available software packages
as pre-compiled binaries in an tar-gz archive (directory *packages*).

NOTE: The prototype is only supporting the naming scheme *application-name_version-info*
      For example: *program1_2.3.1*

For releases there is a second directory which constains symbolic links to the 
actual packages in the packages directory.

Additionally, there needs to be file called *repository_content.txt* in the repository
root (that is where the directories *packages* and *releases* are). This text file
contains the current layout of the repository. 

To find out about packages in the repository *stow-manager* will only work with
the file *repository_content.txt*, it won't scan the web server on its own.

The content of *repository_content.txt* of our example drawing would be:

    /packages/prog1_4.2.1.tar.gz               
    /packages/prog1_4.2.2.tar.gz               
    /packages/prog2_3.2.4.tar.gz               
    /packages/prog2_3.4.2.tar.gz               
    /releases/firstRelease/prog1_4.2.1.tar.gz  
    /releases/firstRelease/prog2_3.2.4.tar.gz  
    /releases/secondRelease/prog1_4.2.2.tar.gz 
    /releases/secondRelease/prog2_3.4.2.tar.gz 

The stow-manager is expecting this repository layout as a prerequisite but is 
not offering any support here. You have to write your own scripts in order 
to generate this structure.

## Using *stow-manager*
      
On *MY COMPUTER* (see drawing) there are two directories, the staging area (just a more
convinient name for the *stow directory*) and the root directory (in stow
terms this is the *target directory*).

When installing a package via the stow-manager, it is first downloaded from the
repository, extracted in the staging area and then installed into the root
directory, using *stow* in the background. 

*stow* is using an intelligent symbolic link mechanism for this task. 
So all files and directories which are installed from the staging area to the 
root directory are only symbolic links. This is the core philosophy of *stow*.

## Component vs Package

*stow-manager* is differentiating between a component and a package. 
In the example drawing, *prog1* would be a component, *prog1_4.2.1* and *prog1_4.2.2*
are packages.

The idea is that if you type *install prog1* automatically the latest package
version ( = the one with the highest version number ) is installed. 
Alternatively, you can install a concret package like *install prog1_4.2.1*

## Releases

A release is just a bundle of software packages which are tried to be installed/ 
upgraded after another.

See function *processRelease* for details.

## Online Help

    Stow Manager 0.5
    
    Usage:  stow_manager.sh [options...] sub-command [arguments...]
    
    Package manipulation
    --------------------
    install <component>/<pkg>        install component or package from repository
    remove <component>/<pkg>         remove a component or package
    upgrade <component>/<pkg>        upgrade a component or package
    purge_unused                     delete unused packages from staging area   
    
    Release management
    ------------------
    upgrade_release <release name>   upgrade installed packages to version of release
    stage_release <release name>     only download release packages to staging area 
    
    List packages and files
    -----------------------
    list_installed                   list installed packages
    list_packages                    lists all packages in the repository
    list_releases                    list available releases
    list_release <release name>      list all packages of a release
    list_unused                      list unused packages in the staging area
    list_repo                        list content of the repository
    find_package <file>              find the package a file is belonging to
    files <pkg>                      list all files of a package
    
    update                           get fresh package list from repository
    status                           display repository status    
    
    Options
    -------
    -n                               no files are changed, only simulate actions
    -v <number>                      increase verbosity of package manipulation 
                                   sub-commands. levels are 0,1,2,3. default is 0

## Installation and Usage

Running *stow-manager* is straight forward. 

The following three environment variables need to be set:

### PKG_REPOSITORY_URL

The URL of the package repository on the web server, containing
the directories *packages* and *releases*.

### PKG_STAGING_AREA 

Directory of the staging area (the *stow* dir)

### PKG_ROOT_DIR 

Directory where packages should go to ( the *target dir* in *stow*)                     

Now execute *stow_manager.sh update* to initially fetch the repository content file.

## Advantages Of A Stow Based Package Manager

*stow* was invented for easy, non-root installation of software packages.

The core idea of *stow* is to use the symbolic link mechanism of the operating system.
Nothing is copied to the root directory, everything is just linked.

Hence, *stow-manager* does not required a package database in contrast to *dpkg* or *rpm*.
Information like *list of installed packages* is only derived from the symbolic links
between the staging area (= stow directory) and the root dir ( = *target dir* in stow terms).

See function *listInstalledPackages* for an idea how this is accomplished.

## Result Of Prototyping

Since it was assumed that the missing functionality is "just some additional 
Linux commands" Bash was chosen as implementation language. However, with every 
single feature added I felt the Python/ Ruby/ Perl would have been much better 
canditates - even for this prototype.  
This is mainly due to very limited semantic checking of Bash and the lack of 
generating modules/ classes.  Bash simply never has been designed to accommodate 
larger logic.

In terms of programing style I hope that *stow_manager.sh* can serve an example
for clean coding - even with Bash.

## Future Work

If somebody wants to pick up on my work, here is what I would have done next:

If staying with Bash as language, I would try to split the source files into
groups of functions belonging together. In a build script I would finally attach
them together to *stow-manager.sh* again.

This is purlely to prevent one big file but rather having multiple, more specific
ones. However, the limited namespace (no modules/ classes...) is still the same.

I personally would rewrite the manager with a proper scripting language but would
still continue to use the power and simplicity of the GNU *find* command to quickly
fetch the installed symbolic links. The output of *find* (runs as child process)
would then be further evaluated internally.

Additionally, switching to e.g. Python would make unit testing (which is currently missing) 
simple.
