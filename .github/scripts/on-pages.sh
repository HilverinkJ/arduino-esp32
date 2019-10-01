#/bin/bash


EVENT_JSON=`cat $GITHUB_EVENT_PATH`

pages_added=`echo "$EVENT_JSON" | jq -r '.commits[].added[]'`
pages_modified=`echo "$EVENT_JSON" | jq -r '.commits[].modified[]'`
pages_removed=`echo "$EVENT_JSON" | jq -r '.commits[].removed[]'`

echo "Event: $GITHUB_EVENT_NAME, Repo: $GITHUB_REPOSITORY, Path: $GITHUB_WORKSPACE, Ref: $GITHUB_REF"
echo
echo "Commits: "
echo "  Added: $pages_added"
echo "  Modified: $pages_modified"
echo "  Removed: $pages_removed"
echo

for page in $pages_added; do
	if [[ $page != "README.md" && $page != "docs/"* ]]; then
		echo "Skipping '$page'"
		continue
	fi
	echo "Adding '$page' to pages ..."
done

for page in $pages_modified; do
	if [[ $page != "README.md" && $page != "docs/"* ]]; then
		echo "Skipping '$page'"
		continue
	fi
	echo "Modifying '$page' ..."
done

for page in $pages_removed; do
	if [[ $page != "README.md" && $page != "docs/"* ]]; then
		echo "Skipping '$page'"
		continue
	fi
	echo "Removing '$page' from pages ..."
done
