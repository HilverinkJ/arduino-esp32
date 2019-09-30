#!/bin/bash

function downloadAndMergePackageJSON(){
	local jsonLink=$1
	local jsonOut=$2
	local old_json=$OUTPUT_DIR/oldJson.json
	local merged_json=$OUTPUT_DIR/mergedJson.json
	
	echo "Downloading previous JSON $jsonLink ..."
	curl -L -o "$old_json" "https://github.com/$GITHUB_REPOSITORY/releases/download/$jsonLink?access_token=$GITHUB_TOKEN"
	if [ $? -ne 0 ]; then echo "ERROR: Download Failed! $?"; exit 1; fi

	echo "Creating new JSON ..."
	set +e
	stdbuf -oL python "$GITHUB_WORKSPACE/package/merge_packages.py" "$jsonOut" "$old_json" > "$merged_json"
	set -e	#supposed to be ON by default
	
	set -v
	if [ ! -s $merged_json ]; then
		rm -f "$merged_json"
		echo " Done: nothing to merge ($merged_json empty) => $jsonOut remains unchanged"
	else
		rm -f "$jsonOut"
		mv "$merged_json" "$jsonOut"
		echo " Done: JSON data successfully merged to $jsonOut"
	fi
	rm -f "$old_json"
	set +v
}

echo "Getting previous releases ..."
releasesJson=`curl -sH "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/$GITHUB_REPOSITORY/releases`
if [ $? -ne 0 ]; then echo "ERROR: Get Releases Failed! ($?)"; exit 1; fi
echo "$releasesJson"

prev_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false and .prerelease == false)) | sort_by(.created_at | - fromdateiso8601) | .[0].tag_name')
prev_any_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false)) | sort_by(.created_at | - fromdateiso8601)  | .[0].tag_name')
prev_pre_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false and .prerelease == true)) | sort_by(.created_at | - fromdateiso8601)  | .[0].tag_name')

shopt -s nocasematch
if [ "$prev_any_release" == "$RELEASE_TAG" ]; then
	prev_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false and .prerelease == false)) | sort_by(.created_at | - fromdateiso8601) | .[1].tag_name')
	prev_any_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false)) | sort_by(.created_at | - fromdateiso8601)  | .[1].tag_name')
	prev_pre_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false and .prerelease == true)) | sort_by(.created_at | - fromdateiso8601)  | .[1].tag_name')
fi
shopt -u nocasematch

set -e

echo "     previous Release: $prev_release"
echo "     previous Pre-release: $prev_pre_release"
echo "     previous (any)release: $prev_any_release"

# add generated items to JSON package-definition contents
jq_arg=".packages[0].platforms[0].version = \"$RELEASE_TAG\" | \
    .packages[0].platforms[0].url = \"$PKG_URL\" |\
    .packages[0].platforms[0].archiveFileName = \"$PKG_ZIP\" |\
	.packages[0].platforms[0].size = \"$PKG_SIZE\" |\
	.packages[0].platforms[0].checksum = \"SHA-256:$PKG_SHA\""
 

PACKAGE_JSON_DEV="package_esp32_dev_index.json"
PACKAGE_JSON_REL="package_esp32_index.json"

# always get DEV version of JSON (included in both RC/REL)
echo "Genarating $PACKAGE_JSON_DEV ..."
cat "$GITHUB_WORKSPACE/package/package_esp32_index.template.json" | jq "$jq_arg" > "$OUTPUT_DIR/$PACKAGE_JSON_DEV"
if [ ! -z "$prev_any_release" ] && [ "$prev_any_release" != "null" ]; then
	downloadAndMergePackageJSON "$prev_any_release/$PACKAGE_JSON_DEV" "$OUTPUT_DIR/$PACKAGE_JSON_DEV"
	echo "Getting commits from $prev_any_release ..."
	git -C "$GITHUB_WORKSPACE" log --oneline $prev_any_release.. > "$OUTPUT_DIR/commits.txt"
fi
echo "Uploading $PACKAGE_JSON_DEV ..."
echo "Download URL: "`git_safe_upload_asset "$OUTPUT_DIR/$PACKAGE_JSON_DEV"`

# for RELEASE run update REL JSON as well
if [ "$RELEASE_PRE" == "false" ]; then
	echo "Genarating $PACKAGE_JSON_REL ..."
	cat "$GITHUB_WORKSPACE/package/package_esp32_index.template.json" | jq "$jq_arg" > "$OUTPUT_DIR/$PACKAGE_JSON_REL"
	if [ ! -z "$prev_release" ] && [ "$prev_release" != "null" ]; then
		downloadAndMergePackageJSON "$prev_release/$PACKAGE_JSON_REL" "$OUTPUT_DIR/$PACKAGE_JSON_REL"
		echo "Getting commits from $prev_release ..."
		git -C "$GITHUB_WORKSPACE" log --oneline $prev_release.. > "$OUTPUT_DIR/commits.txt"
	fi
	echo "Uploading $PACKAGE_JSON_REL ..."
	echo "Download URL: "`git_safe_upload_asset "$OUTPUT_DIR/$PACKAGE_JSON_REL"`
fi

echo
echo "JSON definition file(s) creation OK"

set +e
