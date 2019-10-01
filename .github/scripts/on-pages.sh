#/bin/bash


EVENT_JSON=`cat $GITHUB_EVENT_PATH`

echo "Event: $GITHUB_EVENT_NAME, Repo: $GITHUB_REPOSITORY, Path: $GITHUB_WORKSPACE, Ref: $GITHUB_REF"
echo
echo "Commits: "
echo "  Added: "`echo "$EVENT_JSON" | jq -r '.commits.added'
echo "  Modified: "`echo "$EVENT_JSON" | jq -r '.commits.modified'
echo "  Removed: "`echo "$EVENT_JSON" | jq -r '.commits.removed'
echo
echo "Head Commit: "
echo "  Added: "`echo "$EVENT_JSON" | jq -r '.head_commit.added'
echo "  Modified: "`echo "$EVENT_JSON" | jq -r '.head_commit.modified'
echo "  Removed: "`echo "$EVENT_JSON" | jq -r '.head_commit.removed'
echo
