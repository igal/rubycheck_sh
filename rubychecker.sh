#!/bin/bash

# Please run this program with "-h" or see the "README.txt"  for
# information on this program and how to use it.

#=======================================================================

# Display usage
usage () {
    cat $(dirname $0)"/README.txt"
}

#===[ Settings ]========================================================

# Sources
RAILS_SOURCE="git://github.com/rails/rails.git"
RSPEC_SOURCE="git://github.com/dchelimsky/rspec.git"
RUBYSPEC_SOURCE="git://github.com/rubyspec/rubyspec.git"
RUBYGEMS_SOURCE="http://rubyforge.org/frs/download.php/38647/rubygems-1.2.0.zip"

#===[ Functions ]=======================================================

# Switch into directory, silently.
pushds () {
    local dir="$1"

    pushd "$dir" > /dev/null
}

# Return to previous directory, silently.
popds () {
    popd > /dev/null
}

# Display error message and exit with error.
fail () {
    local message="$1"

    echo "ERROR: $message"
    exit 1
}

# Download the specified URL into the current directory.
download () {
    local url=$1
    wget --version > /dev/null 2>&1
    if [ $? = 0 ]; then
        wget --continue --timeout=10 "$url"
    else
        target=$(basename $url)
        ruby -e "require 'open-uri'; File.open('$target', 'w+'){|h| h.write(open('$url').read) }"
    fi
}

# Prepare the RubyGems application
prepare_rubygems () {
    ruby -e 'require "rubygems"' > /dev/null 2>&1
    if [ $? != 0 ]; then
        pushds "$CACHE_DIR"
            if [ -d "rubygems" ]; then
                echo "* rubygems already installed"
            else
                download "$RUBYGEMS_SOURCE"
                unzip $(basename "$RUBYGEMS_SOURCE")
                mv $(basename "$RUBYGEMS_SOURCE" .zip) "rubygems"
            fi

            pushds "rubygems"
                ruby "setup.rb" --no-ri --no-rdoc
            popds
        popds
    fi
    export PATH="$(gem env path)/bin:$PATH"
}

# Prepare Gem libraries
prepare_gems () {
    # TODO cache downloaded gems locally

    pushds "$GEMS_DIR"
        packages_to_install=""

        for package in rake sqlite3-ruby mysql rake diff-lcs syntax mocha rcov heckle hpricot mspec; do
            gem list --local "$package" | grep -q "$package"
            if [ $? != 0 ]; then
                packages_to_install="$packages_to_install $package"
            fi
        done

        if [ -n "$packages_to_install" ]; then
            gem install $packages_to_install --no-ri --no-rdoc
        fi
    popds
}

# Checkout or freshen Git code from URL
prepare_git_checkout () {
    local url="$1"
    local dir=$(basename "$url" .git)

    pushds "$CACHE_DIR"
        if [ -d "$dir" ]; then
            echo "* updating git checkout: $dir"
            pushds "$dir"
                git checkout -f master
                git pull --rebase origin master
                git fetch --tags
            popds
        else
            echo "* checking out git repository: $url"
            git clone "$url"
        fi
    popds
}

# Prepare source code checkouts
prepare_checkouts () {
    if [ $SKIP_CHECKOUTS = 1 ]; then
        return 0
    else
        prepare_git_checkout "$RAILS_SOURCE"
        prepare_git_checkout "$RSPEC_SOURCE"
        prepare_git_checkout "$RUBYSPEC_SOURCE"
    fi
}

# Prepare dependencies
prepare () {
    prepare_checkouts
    prepare_rubygems
    prepare_gems
}

# Check test suites
check () {
    check_rubyspec
    check_rspec
    check_rails
}

check_rubyspec () {
    pushds "${CACHE_DIR}/rubyspec/1.8"
        mspec . 2>&1 | tee "${REPORTS_DIR}/rubyspec_with_${TAG}.log"
    popds
}

check_rspec () {
    pushds "${CACHE_DIR}/rspec"
        local version=1.1.4
        git checkout -f "$version" # TODO extract hardcoded versions
        rake spec 2>&1 | tee "${REPORTS_DIR}/rspec_${version}_with_${TAG}.log"
    popds
}

check_rails () {
    pushds "${CACHE_DIR}/rails"
        local version="2.1.0"
        git checkout -f "$version"
        rake test 2>&1 | tee "${REPORTS_DIR}/rails_${version}_with_${TAG}.log"

        local version="2.0.2"
        git checkout -f "$version"
        rake test 2>&1 | tee "${REPORTS_DIR}/rails_${version}_with_${TAG}.log"

        local version="1.2.6"
        local log="${REPORTS_DIR}/rails_${version}_with_${TAG}.log"
        git checkout -f "$version"
        cat /dev/null > "$log"
        for f in `find * -maxdepth 0 -type d`; do
            (cd $f && rake test) 2>&1 | tee -a "$log"
        done
    popds
}

#===[ Main ]============================================================

# Defaults
BASE_DIR="$PWD"
TAG="current"
SKIP_CHECKOUTS=0

# Process arguments
while getopts ':ht:vGRSC' OPTION
do
    case $OPTION in
    h)
        usage
        exit 0
        ;;
    t)
        TAG="$OPTARG"
        ;;
    v)
        echo "rubychecker 0.0.1"
        exit 0
        ;;
    S)
        SKIP_CHECKOUTS=1
        ;;
    C)
        SKIP_CHECKOUTS=1
        ;;
    ?)
        echo "Unknown option: $OPTARG"
        exit 2
        ;;
    esac
done
shift $(($OPTIND - 1))

# Set paths
REPORTS_DIR="$BASE_DIR/reports"
CACHE_DIR="$BASE_DIR/cache"
GEMS_DIR="$BASE_DIR/cache/gems"

# Check arguments
if ! [ "$BASE_DIR" ]; then
    fail "Base directory not specified, see --help"
fi

# Create directories
if ! [ -d "$BASE_DIR" ]; then mkdir -p "$BASE_DIR"; fi
if ! [ -d "$CACHE_DIR" ]; then mkdir -p "$CACHE_DIR"; fi
if ! [ -d "$REPORTS_DIR" ]; then mkdir -p "$REPORTS_DIR"; fi
if ! [ -d "$GEMS_DIR" ]; then mkdir -p "$GEMS_DIR"; fi

prepare
check

#===[ Fin ]=============================================================
