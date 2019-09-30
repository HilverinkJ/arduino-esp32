#!/bin/bash

if [ ! $GITHUB_EVENT_NAME == "release" ]; then
    echo "Wrong event '$GITHUB_EVENT_NAME'!"
    exit 1
fi

EVENT_JSON=`cat $GITHUB_EVENT_PATH`
action=`echo $EVENT_JSON | jq -r '.action'`
export RELEASE_DRAFT=`echo $EVENT_JSON | jq -r '.release.draft'`
export RELEASE_PRE=`echo $EVENT_JSON | jq -r '.release.prerelease'`
export RELEASE_TAG=`echo $EVENT_JSON | jq -r '.release.tag_name'`
export RELEASE_BRANCH=`echo $EVENT_JSON | jq -r '.release.target_commitish'`
export RELEASE_ID=`echo $EVENT_JSON | jq -r '.release.id'`

echo "Event: $GITHUB_EVENT_NAME, Repo: $GITHUB_REPOSITORY, Path: $GITHUB_WORKSPACE, Ref: $GITHUB_REF"
echo "Action: $action, Branch: $RELEASE_BRANCH, ID: $RELEASE_ID" 
echo "Tag: $RELEASE_TAG, Draft: $RELEASE_DRAFT, Pre-Release: $RELEASE_PRE"

if [ $RELEASE_DRAFT == "true" ]; then
	echo "It's a draft release. Exiting now..."
	exit 0
fi

if [ ! $action == "published" ]; then
	echo "Wrong action '$action'. Exiting now..."
	exit 0
fi

function get_file_size(){
    local file="$1"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        eval `stat -s "$file"`
        local res="$?"
        echo "$st_size"
        return $res
    else
        stat --printf="%s" "$file"
        return $?
    fi
}

function git_upload_asset(){
    local name=$(basename "$1")
    # local mime=$(file -b --mime-type "$1")
    curl -k -X POST -sH "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" -H "Content-Type: application/octet-stream" -data-binary @"$1" "https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?name=$name"
}

function git_safe_upload_asset(){
    local file="$1"
    local name=$(basename "$file")
    local size=`get_file_size "$file"`
    local upload_res=`git_upload_asset "$file"`
    if [ $? -ne 0 ]; then 
        >&2 echo "ERROR: Failed to upload '$name' ($?)"
        return 1
    fi
    up_size=`echo "$upload_res" | jq -r '.size'`
    if [ $up_size -ne $size ]; then
        >&2 echo "ERROR: Uploaded size does not match! $up_size != $size"
        #git_delete_asset
        return 1
    fi
    echo "$upload_res" | jq -r '.browser_download_url'
    return $?
}

function git_upload_to_pages(){
    local path=$1
    local src=$2

    if [ ! -f "$src" ]; then
        echo "Input is not a file! Aborting..."
        return 1
    fi

    local info=`curl -s -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.object+json" -X GET "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$path?ref=gh-pages"`
    local type=`echo "$info" | jq -r '.type'`
    local message=$(basename $path)
    local sha=""
    local content=""

    if [ $type == "file" ]; then
        sha=`echo "$info" | jq -r '.sha'`
        sha=",\"sha\":\"$sha\""
        message="Updating $message"
    elif [ ! $type == "null" ]; then
        echo "Wrong type '$type'"
        return 1
    else
        message="Creating $message"
    fi

    content=`base64 -i "$src"`
    data="{\"branch\":\"gh-pages\",\"message\":\"$message\",\"content\":\"$content\"$sha}"

    echo "$data" | curl -s -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" -X PUT --data @- "https://api.github.com/repos/$GITHUB_REPOSITORY/contents/$path"
}

# good time to build the assets
#if [ $RELEASE_PRE == "true" ]; then
#	echo "It's a pre-release"
#fi

# upload asset to the release page
#git_upload_asset ./README.md

# upload file to github pages
#git_upload_to_pages README.md ./README.md

export OUTPUT_DIR="$GITHUB_WORKSPACE/build"
mkdir -p "$OUTPUT_DIR"

source "$GITHUB_WORKSPACE/tools/ci/create-package-zip.sh"

set -e
echo "Generating submodules.txt ..."
git -C "$GITHUB_WORKSPACE" submodule status > "$OUTPUT_DIR/submodules.txt"
echo "Uploading submodules.txt ..."
echo "Download URL: "`git_safe_upload_asset "$OUTPUT_DIR/submodules.txt"`
echo ""
set +e















