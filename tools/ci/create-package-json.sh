#!/bin/bash

function merge_package_json(){
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
		echo "Nothing to merge"
	else
		rm -f "$jsonOut"
		mv "$merged_json" "$jsonOut"
		echo "JSON data successfully merged"
	fi
	rm -f "$old_json"
	set +v
}

PACKAGE_JSON_DEV="package_esp32_dev_index.json"
PACKAGE_JSON_REL="package_esp32_index.json"

echo "Getting previous releases ..."
releasesJson=`curl -sH "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/$GITHUB_REPOSITORY/releases"`
if [ $? -ne 0 ]; then echo "ERROR: Get Releases Failed! ($?)"; exit 1; fi

prev_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false and .prerelease == false)) | sort_by(.created_at | - fromdateiso8601) | .[0].tag_name')
prev_any_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false)) | sort_by(.created_at | - fromdateiso8601)  | .[0].tag_name')
shopt -s nocasematch
if [ "$prev_any_release" == "$RELEASE_TAG" ]; then
	prev_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false and .prerelease == false)) | sort_by(.created_at | - fromdateiso8601) | .[1].tag_name')
	prev_any_release=$(echo "$releasesJson" | jq -e -r '. | map(select(.draft == false)) | sort_by(.created_at | - fromdateiso8601)  | .[1].tag_name')
fi
COMMITS_SINCE_RELEASE="$prev_any_release"
shopt -u nocasematch

echo "Previous Release: $prev_release"
echo "Previous (any)release: $prev_any_release"

set -e

# add generated items to JSON package-definition contents
jq_arg=".packages[0].platforms[0].version = \"$RELEASE_TAG\" | \
    .packages[0].platforms[0].url = \"$PKG_URL\" |\
    .packages[0].platforms[0].archiveFileName = \"$PKG_ZIP\" |\
	.packages[0].platforms[0].size = \"$PKG_SIZE\" |\
	.packages[0].platforms[0].checksum = \"SHA-256:$PKG_SHA\""
 
# always get DEV version of JSON (included in both RC/REL)
echo "Genarating $PACKAGE_JSON_DEV ..."
cat "$GITHUB_WORKSPACE/package/package_esp32_index.template.json" | jq "$jq_arg" > "$OUTPUT_DIR/$PACKAGE_JSON_DEV"
if [ ! -z "$prev_any_release" ] && [ "$prev_any_release" != "null" ]; then
	merge_package_json "$prev_any_release/$PACKAGE_JSON_DEV" "$OUTPUT_DIR/$PACKAGE_JSON_DEV"
	echo "Getting commits from $prev_any_release ..."
	git -C "$GITHUB_WORKSPACE" log --oneline $prev_any_release.. > "$OUTPUT_DIR/commits.txt"
fi
echo "Uploading $PACKAGE_JSON_DEV ..."
echo "Download URL: "`git_safe_upload_asset "$OUTPUT_DIR/$PACKAGE_JSON_DEV"`

# for RELEASE run update REL JSON as well
if [ "$RELEASE_PRE" == "false" ]; then
	COMMITS_SINCE_RELEASE="$prev_release"
	echo "Genarating $PACKAGE_JSON_REL ..."
	cat "$GITHUB_WORKSPACE/package/package_esp32_index.template.json" | jq "$jq_arg" > "$OUTPUT_DIR/$PACKAGE_JSON_REL"
	if [ ! -z "$prev_release" ] && [ "$prev_release" != "null" ]; then
		merge_package_json "$prev_release/$PACKAGE_JSON_REL" "$OUTPUT_DIR/$PACKAGE_JSON_REL"
	fi
	echo "Uploading $PACKAGE_JSON_REL ..."
	echo "Download URL: "`git_safe_upload_asset "$OUTPUT_DIR/$PACKAGE_JSON_REL"`
fi

echo "JSON definition file(s) created"
echo

export COMMITS_SINCE_RELEASE

#
# Prepare Markdown release notes:
#################################
# - annotated tags only, lightweight tags just display message of referred commit
# - tag's description conversion to relnotes:
# 	first 3 lines (tagname, commiter, blank): ignored
#	4th line: relnotes heading
#	remaining lines: each converted to bullet-list item
#	empty lines ignored
#	if '* ' found as a first char pair, it's converted to '- ' to keep bulleting unified
echo "Preparing release notes ..."
relNotesRaw=`git -C "$GITHUB_WORKSPACE" show -s --format=%b $RELEASE_TAG`
readarray -t msgArray <<<"$relNotesRaw"
arrLen=${#msgArray[@]}
releaseNotes=""
#process annotated tags only
if [ $arrLen > 3 ] && [ "${msgArray[0]:0:3}" == "tag" ]; then 
	ind=3
	while [ $ind -lt $arrLen ]; do
		if [ $ind -eq 3 ]; then
			releaseNotes="#### ${msgArray[ind]}"
			releaseNotes+=$'\r\n'
		else
			oneLine="$(echo -e "${msgArray[ind]}" | sed -e 's/^[[:space:]]*//')"
			
			if [ ${#oneLine} -gt 0 ]; then
				if [ "${oneLine:0:2}" == "* " ]; then oneLine=$(echo ${oneLine/\*/-}); fi
				if [ "${oneLine:0:2}" != "- " ]; then releaseNotes+="- "; fi		
				releaseNotes+="$oneLine"
				releaseNotes+=$'\r\n'
				
				#debug output
				echo "   ${oneLine}"
			fi
		fi
		let ind=$ind+1
	done
fi

if [ ! -z "$COMMITS_SINCE_RELEASE" ] && [ "$COMMITS_SINCE_RELEASE" != "null" ]; then
	echo "Getting commits from $COMMITS_SINCE_RELEASE ..."
	commitFile=$OUTPUT_DIR/commits.txt
	git -C "$GITHUB_WORKSPACE" log --oneline $COMMITS_SINCE_RELEASE.. > "$OUTPUT_DIR/commits.txt"
	releaseNotes+=$'\r\n##### Commits\r\n'
	IFS=$'\n'
	for next in `cat $commitFile`
	do
		IFS=' ' read -r commitId commitMsg <<< "$next"
		commitLine="- [$commitId](https://github.com/$GITHUB_REPOSITORY/commit/$commitId) $commitMsg"
		releaseNotes+="$commitLine"
		releaseNotes+=$'\r\n'
	done
	rm -f $commitFile
fi

echo "Tag's message:"
echo "$releaseNotes"
echo

#Merge release notes and overwrite pre-release flag. all other attributes remain unchanged:

# 1. take existing notes from server (added by release creator)
releaseNotesGH=$(echo $EVENT_JSON | jq -r '.release.body')

# - strip possibly trailing CR
if [ "${releaseNotesGH: -1}" == $'\r' ]; then 		
	releaseNotesTemp="${releaseNotesGH:0:-1}"
else 
	releaseNotesTemp="$releaseNotesGH"
fi
# - add CRLF to make relnotes consistent for JSON encoding
releaseNotesTemp+=$'\r\n'

# 2. #append generated relnotes (usually commit oneliners)
releaseNotes="$releaseNotesTemp$releaseNotes"

# 3. JSON-encode whole string for GH API transfer
releaseNotes=$(printf '%s' "$releaseNotes" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# 4. remove extra quotes returned by python (dummy but whatever)
releaseNotes=${releaseNotes:1:-1}

#Update current GH release record
echo " - updating release notes and pre-release flag:"

curlData="{\"body\": \"$releaseNotes\",\"prerelease\": $RELEASE_PRE}"
echo "   <data.begin>$curlData<data.end>"
echo

curl --data "$curlData" "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID?access_token=$GITHUB_TOKEN"
if [ $? -ne 0 ]; then echo "FAILED: $? => aborting"; exit 1; fi

echo " - release record successfully updated"

set +e
