#!/bin/bash

set -e

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

# take existing notes from server (added by release creator)
releaseNotesGH=$(echo $EVENT_JSON | jq -r '.release.body')
if [ "${releaseNotesGH: -1}" == $'\r' ]; then 		
	releaseNotesTemp="${releaseNotesGH:0:-1}"
else 
	releaseNotesTemp="$releaseNotesGH"
fi
releaseNotesTemp+=$'\r\n'
releaseNotes="$releaseNotesTemp$releaseNotes"

echo "Release Notes:"
echo "$releaseNotes"
echo

#Update current GH release record
echo "Updating release notes ..."
releaseNotes=$(printf '%s' "$releaseNotes" | python -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
releaseNotes=${releaseNotes:1:-1}
curlData="{\"body\": \"$releaseNotes\"}"
releaseData=`curl --data "$curlData" "https://api.github.com/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID?access_token=$GITHUB_TOKEN" 2>/dev/null`
if [ $? -ne 0 ]; then echo "ERROR: Updating Release Failed: $?"; exit 1; fi
echo "Release notes successfully updated"
echo

set +e
