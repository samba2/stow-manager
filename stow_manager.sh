#/bin/bash

########################################################################
#
#  Stow-Manager
#
#  Working prototype of a simple package manager based on symbolic links.
#  The core functionality (installing, removing... ) is provided by 
#  the GNU tool 'stow'.
#
#  "Informational commands" as well as support for a simple http based
#  repository is implemented based on Linux shell commands.
#
#  2014, Maik Toepfer
#
########################################################################

# TODO display warning if no respository file is present
# TODO multiple packages as argument for install, update, remove

SCRIPT_VERSION="0.5"

# e.g. abc_3.1.2
PACKAGE_NAME_REGEX='^[[:alnum:]]{3,5}_[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+$'

# declare global vars
g_optionSimulate=
g_optionDisplayCommand=
g_optionVerbose=
g_verboseLevel=
g_subCommand=
g_packageParam=
g_stow=
g_wget=

g_helpText="
  Stow Manager ${SCRIPT_VERSION}

  Usage:  $0 [options...] sub-command [arguments...]

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
"

function main {
    local args=( "$@" )

    processEnvironmentVariables 
    setupRequiredCommands
    processOptions "${args[@]}"

    case "${g_subCommand}" in
        update) updatePackageList; shift;;
        install) installPackage "${g_packageParam}"; shift;;
        upgrade) upgradePackage "${g_packageParam}"; shift;;
        remove) removePackage "${g_packageParam}"; shift;;
        stage_release) stageRelease "${g_packageParam}"; shift;;
        upgrade_release) upgradeRelease "${g_packageParam}"; shift;;
        purge_unused) purgeUnusedPackages; shift;; 
        list_installed) listInstalledPackages; shift;;
        list_packages) listRepoPackages; shift;;
        list_unused) listUnusedPackages; shift;;
        list_repo) listRepository; shift;;
        list_releases) listReleases; shift;;
        list_release) listReleasePackages "${g_packageParam}"; shift;; 
        files) listAllFilesOfPackage ${g_packageParam}; shift;;
        find_package) findPackageForFile ${g_packageParam}; shift;;
        status) displayStatus; shift;;
        
        *) echo "${g_helpText}" ; exit;;
    esac
}

#---------- Package Commands -----------------
function updatePackageList {
    local repositoryFile=`getRepositoryFilePath`
    printInformation "Fetching fresh package list from repository ${PKG_REPOSITORY_URL}"

    local errMsg=
    if ! errMsg=`downloadFile "${PKG_REPOSITORY_URL}repository_content.txt" "${repositoryFile}"`; then
       printAndExit "${errMsg}" 1
    fi
}

function installPackage {
    local packageParam=$1

    doCheckValidPackageParam "${packageParam}"
    doCheckComponentIsNotInstalled "${packageParam}"
    # if packageParam is a package name, see if its in repository
    doCheckPackageExists "${packageParam}"

    local packageName=`getPackageNameToInstall "${packageParam}"`
    doCheckPackage "${packageName}" "${packageParam}"

    doIfNotPresentGetPackageFromRepository "${packageName}"

    stowPackage "${packageName}"
}

function upgradePackage {
    local packageParam=$1

    doCheckValidPackageParam "${packageParam}"
    doCheckComponentIsInstalled "${packageParam}"
    # if packageParam is a package name, see if its in repository
    doCheckPackageExists "${packageParam}"

    local oldPackage=    

    # if new package was supplied, get installed package via component name
    if isValidPackageName "${packageParam}"; then
        local component=`getComponentNameFromPackage "${packageParam}"`
        oldPackage=`getInstalledPackage "${component}"`
    else
        # a comonent was supplied
        oldPackage=`getInstalledPackage "${packageParam}"`
    fi
    
    local newPackage=

    # here it is easier to resolve via component name
    if isValidComponentName "${packageParam}"; then
        newPackage=`getMostRecentPackage "${packageParam}"`
    else
        newPackage=${packageParam}     
    fi

    local msg=

    if [ ! "${newPackage}" ]; then
        local componentName=`getComponentNameFromPackage "${packageParam}"`

        printAndExit "Repository does not contain a package for component '${componentName}'" 1

    # TODO better message for upgrading via repository or directly with package name
    elif [[ "${oldPackage}" > "${newPackage}" ]]; then
        msg="Downgrading from version ${oldPackage} to version ${newPackage}, continue?"

        doAskAndReplacePackage "${oldPackage}" "${newPackage}" "${msg}"

    elif [[ "${oldPackage}" = "${newPackage}" ]]; then

        if isValidComponentName "${packageParam}"; then
            msg="Installed version ${oldPackage} is already the highest version. " 
        else
            msg="Installed version ${oldPackage} is equal to the new version ${newPackage}, "
        fi
        msg+="Reinstall?"

        doAskAndReplacePackage "${oldPackage}" "${newPackage}" "${msg}"

    elif [[ "${oldPackage}" < "${newPackage}" ]]; then
        doIfNotPresentGetPackageFromRepository "${newPackage}"
        replaceStowPackage "${oldPackage}" "${newPackage}"
    fi 
}

function removePackage {
    local packageParam=$1

    doCheckValidPackageParam "${packageParam}"

    local packageName=`getInstalledPackage "${packageParam}"`

    if [ ! "${packageName}" ]; then
        if isValidComponentName "${packageParam}"; then
            printAndExit "Could not find a package to remove for component '${packageParam}'" 1
        else
            printAndExit "Package '${packageParam}' is not installed" 1
        fi
    fi

    unstowPackage "${packageName}"
}

# if not present in staging area, download all packages of release from repo
function stageRelease {
    local releaseName=$1

    doCheckReleaseExists "${releaseName}"
    processRelease "${releaseName}" "stage"
}
function upgradeRelease {
    local releaseName=$1

    stageRelease "${releaseName}"
    processRelease "${releaseName}" "upgrade"
}

function processRelease {
    local releaseName=$1
    local action=$2

    local installedPackages=( `listInstalledPackages` )

    local package=
    local component=
    local newPackage=

    for package in "${installedPackages[@]}"; do
        component=`getComponentNameFromPackage "${package}"`
        newPackage=`getReleasePackageNameFromComponent "${releaseName}" "${component}"`

        if [ ! "${newPackage}" ]; then
            printInformation "No package in repository for component '${component}'"
            continue
        fi
         
        if [ "${action}" = "stage" ]; then
            doIfNotPresentGetPackageFromRepository "${newPackage}"

        elif [ "${action}" = "upgrade" ]; then
            upgradePackage "${newPackage}"
        fi  
    done
}

function purgeUnusedPackages {
    local unusedPackagesArr=( `listUnusedPackages` )    

    local packagePath=
    for package in "${unusedPackagesArr[@]}"; do

        packagePath="${PKG_STAGING_AREA}/${package}"

        if [ -d "${packagePath}" ]; then
            printInformation "Removing unused package ${package} from staging area"
            rm -rf "${packagePath}"
        fi
    done
}

#---------- List Commands -----------------

function listInstalledPackages {
    local stagingAreaDir=`basename "${PKG_STAGING_AREA}"`
    
    # any line optionally starting with some data, followed by the name of the repository,
    # then followed by a "/", the package name is anything which is not an "/", this is closed by a "/"
    # and followed by other data.
    #
    # example: "../stow_repo/aa2/exe/bin2" would return "app2"
    #          "stow_repo/app1/bin" would return "app1" 
    local singlePackageRegex="^.*${stagingAreaDir}\/([^\/]+)\/.+$" 

    # find symlinks to root dir, cut out package name and shrink to list
    find ${PKG_ROOT_DIR} -type l -printf '%l\n' | \
    sed -r "s/${singlePackageRegex}/\1/g" | \
    sort | \
    uniq
}

function listRepoPackages {
    listRepositoryPackagesOfArea "packages" | sort
}

function listUnusedPackages {
    local listAvailableTmp=`getTempFile`
    local listInstalledTmp=`getTempFile`

    listPackagesInStagingArea> ${listAvailableTmp}
    listInstalledPackages > ${listInstalledTmp}

    # generate diff and display difference
    diff ${listAvailableTmp} ${listInstalledTmp} | egrep '^< ' | sed 's/^< //g'

    rm -f ${listAvailableTmp}
    rm -f ${listInstalledTmp}
}

function listRepository {
    local repoFilePath=`getRepositoryFilePath`

    if [ -r "${repoFilePath}" ]; then
        cat `getRepositoryFilePath` | sort
    fi
}

function listReleases {
    listRepository | egrep -r "^/releases/" | cut -d "/" -f 3 | sort | uniq
}

function listReleasePackages {
    local releaseName=$1

    doCheckReleaseExists "${releaseName}"
    listRepositoryPackagesOfArea "releases" "${releaseName}" | sort
}

function listAllFilesOfPackage {
    packageName=$1
    checkPackage ${packageName}

    local repo=`getPathWithTrailingSlash "${PKG_STAGING_AREA}"`
    # escape backslashes, "/my_dir/" is now "\/my_dir\/"
    repo=${repo//\//\\/}
        
    # simple listing of package dir content, the repository base path is removed 
    # so that only the package content is displayed.
    # "/my_repo/package1/bin/my_file" will be displayed as "package/bin/my_file"   
    find ${PKG_STAGING_AREA}/${packageName} | sed 's/${repo}//'
}

function listPackagesInStagingArea {
    ls -1 ${PKG_STAGING_AREA} | egrep -r "${PACKAGE_NAME_REGEX}"
}

# returns list of packages ( e.g. abc_1.2.3 ) of a certain
# area inside the repository
function listRepositoryPackagesOfArea {
    local directory1=$1
    local directory2=$2

    local searchPath=${directory1}

    if [ ${directory2} ]; then
        searchPath+="\/${directory2}"
    fi

    local repositoryFile=`getRepositoryFilePath`
    local packageNameRegex="^\/${searchPath}\/(.+)\.tar\.gz$"
    
    listRepository | \
    egrep -r "^/${searchPath}/" | \
    sed -r "s/${packageNameRegex}/\1/g" 
}

function findPackageForFile {
    local filePath=$1

    if [ ! "${filePath}" ]; then
        printAndExit "Please supply a file name."
    fi

    if [ ! -f "${filePath}" ]; then
        printAndExit "File '${filePath}' does not exist."
    fi

    # TODO test if really only a cut is required or if sed + regex should be used
    find ${filePath} -type l -printf '%l\n'  | cut -d '/' -f 3 
}

function displayStatus {
    local cntPackagesInstalled=`listInstalledPackages | wc -l`
    local cntPackagesRepo=`listRepositoryPackagesOfArea "packages" | wc -l`
    local cntReleasesRepo=`listReleases | wc -l`
    local cntPackagesInStagingArea=`listPackagesInStagingArea |  wc -l`
    local cntUnusedPackagesInStagingArea=`listUnusedPackages |  wc -l`
    local rootDir=`getPathWithTrailingSlash "${PKG_ROOT_DIR}"`
    local stagingAreaDir=`getPathWithTrailingSlash "${PKG_STAGING_AREA}"`

    echo ""
    echo "                 Root Directory: ${rootDir}"
    echo "                     Repository: ${PKG_REPOSITORY_URL}"
    echo "                   Staging Area: ${stagingAreaDir}"
    echo ""
    echo "             Installed packages: ${cntPackagesInstalled}"
    echo "         Packages in repository: ${cntPackagesRepo}"
    echo "         Releases in repository: ${cntReleasesRepo}"
    echo "       Packages in staging area: ${cntPackagesInStagingArea}"
    echo "Unused packages in staging area: ${cntUnusedPackagesInStagingArea}"
    echo ""
}

# --------- check functions --------------

function doCheckValidPackageParam {
    local packageParam=$1

    if [ ! "${packageParam}" ]; then
        printAndExit "Component or package name is missing" 1
    fi

    if ! isValidComponentName "${packageParam}" && ! isValidPackageName "${packageParam}"; then
        printAndExit "'${packageParam}' is not a recognized component or package name." 1
    fi
}

# checks whether or not a component is already installed 
# as prerequ. for installation
function doCheckComponentIsNotInstalled {
    local packageParam=$1
    local componentName=`getComponentNameFromPackage "${packageParam}"`
  
    if isComponentInstalled "${componentName}"; then
        printAndExit "Component '${componentName}' is already installed. Use 'upgrade' instead." 1
    fi
}

function doCheckComponentIsInstalled {
    local packageParam=$1
    local componentName=`getComponentNameFromPackage "${packageParam}"`
  
    if ! isComponentInstalled "${componentName}"; then
        printAndExit "Component '${componentName}' is not installed. Use 'install' first" 1
    fi
}

function doCheckPackageIsInRepository {
    local packageName=$1

    if ! isPackageInRepositoryFile "${packageName}"; then
        printAndExit "Could not find '${packageName}' in repository"
    fi
}

function doAskAndReplacePackage {
    local oldPackage=$1
    local newPackage=$2
    local msg=$3

    echo "${msg}"

    local userResponse=`getUserResponse`
        
    if [ "${userResponse}" = "y" ]; then
        doIfNotPresentGetPackageFromRepository "${newPackage}"
        replaceStowPackage "${oldPackage}" "${newPackage}"
    fi
}

function doCheckPackage {
    local packageName=$1
    local component=$2

    if [ ! "${packageName}" ]; then
        printAndExit "No package for component '${component}' found in repository. Run 'update' and try again." 1
    fi

    if ! isPackageInRepositoryFile "${packageName}"; then
        printAndExit "'${packageName}' was not found in repository. Run 'update' and try again." 1
    fi
}

function doCheckReleaseExists {
    local releaseName=$1

    if [ ! "${releaseName}" ]; then
        printAndExit "Please provide a release name"
    fi

    if ! isValidReleaseName "${releaseName}"; then
        printAndExit "Release '${releaseName}' is not existing. See 'list_repo' for releases available"
    fi
}

function doCheckPackageExists {
    local packageParam=$1

    if isValidPackageName "${packageParam}"; then
        if ! isPackageInRepositoryFile "${packageParam}"; then
            printAndExit "Package '${packageParam}' is not existing. See 'list_repo' for packages available."
        fi   
    fi
}

function checkPackage {
    local packageName=$1

    if [ ! "${packageName}" ]; then
        printAndExit "The package name is not provided."

    elif ! isPackageInStagingArea "${packageName}";  then
        printAndExit "Can't find package '${packageName}' inside the staging area '${PKG_STAGING_AREA}'."
    fi
}

#--------- getter functions -------------------
function getUserResponse {
    local userResponse=

    while [ "${userResponse}" != "y" -a "${userResponse}" != "n" ]; do
        read -p "y/n : " userResponse   
    done

    echo ${userResponse}
}

# if param is a component, return the most recent package of this component
# otherwhise just return param
function getPackageNameToInstall {
    local packageParam=$1
    local packageName=

    if isValidComponentName "${packageParam}"; then
        packageName=`getMostRecentPackage "${packageParam}"`

    else 
        # is already a package name like abc_1.2.3
        packageName=${packageParam}
    fi

    echo "${packageName}"
}

function getReleasePackageNameFromComponent {
    local releaseName=$1
    local component=$2

    listRepositoryPackagesOfArea "releases" "${releaseName}" | \
    egrep -r "^${component}_"     
}

# input "abc_1.2.3", returns "abc"
function getComponentNameFromPackage {
    local package=$1
    echo ${package%%_*}
}

# input is "abc"
# returns e.g. "abc_1.2.3"
function getMostRecentPackage {
    local component=$1

    listRepositoryPackagesOfArea "packages" | \
    egrep -r "^${component}_" |               \
    sort -r | head -n 1
}

# is component e.g. 'abc' is supplied than the actual package
# should return (like 'abc_4.2.1')
# if e.g. abc_4.2.1 then also abc_4.2.1 should be returned (if installed)
function getInstalledPackage {
    listInstalledPackages | egrep -r "^${1}"
}

function getPackageUrl {
    local packageFileName=`getPackageFileName "$1"`
    echo "${PKG_REPOSITORY_URL}/packages/${packageFileName}"
}

function getPackageFileName {
    echo "$1.tar.gz"
}

function getRepositoryFilePath {
    echo "${PKG_STAGING_AREA}/repository_content.txt"
}

function getPathWithTrailingSlash {
    local path=$1

    # add traling slash
    path="${path}/"    

    # delete last double slash, "/my_dir//" becomes "/my_dir/"
    echo $path | sed 's/\/\/$/\//'
}

# build customized stow path
function getStowPath {
    local path="${g_stow} -d ${PKG_STAGING_AREA} -t ${PKG_ROOT_DIR} "
    
    if [ ${g_optionSimulate} ]; then
        path="${path} -n "
    fi

    if [ ${g_optionVerbose} ]; then
        path="${path} -v ${g_verboseLevel} "
    fi

    echo ${path}
}

function getTempFile {
    mktemp -t stow_package_mgr.XXXXX
}

#-------- stowing/ unstowing/ restowing -----------
function stowPackage {
    local packageName=$1

     printInformation "Installing ${packageName} from staging area"

    `getStowPath` -S ${packageName}
}

function unstowPackage {
    local packageName=$1

     printInformation "Removing ${packageName}"

    `getStowPath` -D ${packageName}
}

function replaceStowPackage {
    local oldPackage=$1
    local newPackage=$2

     printInformation "Replacing ${oldPackage} with ${newPackage}"

    `getStowPath` -D ${oldPackage} -S ${newPackage}
}

#-------- boolean functions ----------

function isValidReleaseName {
    local releaseName=$1

    listRepository | egrep -rq "^\/releases/${releaseName}\/"
}


function isComponentInstalled {
    listInstalledPackages | egrep -qr "^${1}_.+"
}

function isPackageInStagingArea {
    listPackagesInStagingArea| egrep -qr "^${1}$"
}

# 'abc' is a comonent string
# 'abc_' or 'abc_4.1.2' is not
function isValidComponentName {
    echo "$1" | grep -qv '_' 
}

# matches e.g. 'abc_4.1.2'
function isValidPackageName {
    echo "$1" | egrep -qr "${PACKAGE_NAME_REGEX}"
}

function isPackageInRepositoryFile {
    local package=$1
    local repositoryFile=`getRepositoryFilePath`

    egrep -qr "^/packages/${package}.tar.gz$" ${repositoryFile}
}

function isPackageInStagingArea {
    test -d "${PKG_STAGING_AREA}/${1}" 
}


#-------- print functions --------------
function printInformation {
    echo "${1}"
}

function printAndExit {
    local text="$1"
    local errorLevel="$2"
    
    # set default error level to "ok"
    if [ ! ${errorLevel} ]; then
        errorLevel=0
    fi
    
    echo -e "${text}"
    exit ${errorLevel}    
}

#-------- misc. functions -----------
function doIfNotPresentGetPackageFromRepository {
    local packageName=$1

    if ! isPackageInStagingArea "${packageName}"; then
        stagePackage "${packageName}"           
    fi
}

function stagePackage {
    local package=$1
    local packageUrl=`getPackageUrl "${package}"`
    local tmpDownloadName=`mktemp -t stow_mgr_package_XXXX.tar.gz`
    local destinationPath="${PKG_STAGING_AREA}/${package}"

    printInformation "Fetching ${package} from repository"

    local errMsg=
    if ! errMsg=`downloadFile "${packageUrl}" "${tmpDownloadName}"`; then
       rm -f ${tmpDownloadName}
       printAndExit "${errMsg}" 1
    fi

    printInformation "Extracting ${package} to staging area"

    mkdir -p ${destinationPath} || printAndExit "Could not create directory ${destinationPath}"

    local output=
    output=`tar xvzf ${tmpDownloadName} -C ${destinationPath} 2>&1`

    if [ $? -ne 0 ]; then
        errorMsg="Error extracting ${tmpDownloadName} to ${destinationPath}\n"
        errorMsg+="Further details (tar output):\n"
        rm -f ${tmpDownloadName}
        printAndExit "${errMsg}" 1
    fi       

    rm -f ${tmpDownloadName}
}

# download remote file to local
# returns 0 or 1 for further error handling in calling function
# additionally an error message is produced on STDOUT
function downloadFile {
    local remoteFileUrl=$1
    local localDestinationFilePath=$2

    local output=
    output=`${g_wget} -O ${localDestinationFilePath} ${remoteFileUrl} 2>&1`

    if [ $? -ne 0 ]; then
        
        local errMsg="\nError downloading '${remoteFileUrl}'\n"
        errMsg+="further details (wget output):\n"
        errMsg+="${output}\n"

        echo "${errMsg}"
        return 1
    fi

    return 0
}

function processEnvironmentVariables {

    if [ ! "${PKG_STAGING_AREA}" ]; then
        printAndExit "The environment variable 'PKG_STAGING_AREA' is not set."
    fi

    if [ ! "${PKG_ROOT_DIR}" ]; then
        printAndExit "The environment variable 'PKG_ROOT_DIR' is not set."
    fi

    if [ ! "${PKG_REPOSITORY_URL}" ]; then
        printAndExit "The environment variable 'PKG_REPOSITORY_URL' is not set."
    fi

    if [ ! -d "${PKG_STAGING_AREA}" ]; then
        printAndExit "The environment variable 'PKG_STAGING_AREA' is currently set to '${PKG_STAGING_AREA}'. This is not a valid directory."
    fi
    
    if [ ! -d "${PKG_ROOT_DIR}" ]; then
        printAndExit "The environment variable 'PKG_ROOT_DIR' is currently set to '${PKG_ROOT_DIR}'. This is not a valid directory."
    fi
    
    # append "/" if required
    PKG_REPOSITORY_URL=`getPathWithTrailingSlash "${PKG_REPOSITORY_URL}"`
}

function setupRequiredCommands {
    g_stow=`which stow` || printAndExit "Can't find command 'stow' in PATH (${PATH})" 1
    g_wget=`which wget` || printAndExit "Can't find command 'wget' in PATH (${PATH})" 1
}

function processOptions {
    local arguments="$@"
    local newPositionalParameters=
    
    newPositionalParameters=`getopt -o ndv: -n 'Stow Manager' -- ${arguments}`
    
    if [ $? -ne 0 ]; then
        echo "${g_helpText}"
        exit 1
    fi

    # set string in newPositionalParameters to be the new positional params of the function
    # enables using of "shift" below
    eval set -- "${newPositionalParameters}"
    
    while true; do
        case "$1" in 
            -n) g_optionSimulate="1"; shift;;
            -d) g_optionDisplayCommand="1"; shift;;
            -v)
                g_optionVerbose="1"
                g_verboseLevel=$2
                shift 2
                ;;
            --) shift ; break ;;
            *) echo "Internal error!" ; exit 1 ;;
        esac
    done

    # remaining parameters are subcommand and (optional) package names
    g_subCommand=$1
    g_packageParam=$2
}


# start main function
main "$@"
