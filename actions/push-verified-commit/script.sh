#!/usr/bin/env bash

set -euo pipefail

local_head=$(git rev-parse HEAD)
remote_url="${SERVER_URL}/${REPOSITORY}.git"

if git diff --cached --quiet; then
	echo "No changes to commit"
else
	tree_oid=$(git write-tree)
	upload_commit=$(printf '%s\n' "$COMMIT_MESSAGE" |
		git \
			-c user.name='github-actions[bot]' \
			-c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
			-c commit.gpgSign=false \
			commit-tree "$tree_oid" -p "$local_head")
	upload_ref="refs/automation/verified-commit-upload/${GITHUB_RUN_ID:-local}-${upload_commit}"

	cleanup() {
		gh api --method DELETE \
			"repos/${REPOSITORY}/git/refs/${upload_ref#refs/}" \
			>/dev/null 2>&1 || true
	}
	trap cleanup EXIT

	gh auth setup-git
	git push "$remote_url" "${upload_commit}:${upload_ref}"

	response=$(jq -n \
		--arg message "$COMMIT_MESSAGE" \
		--arg tree "$tree_oid" \
		--arg parent "$local_head" \
		'{message: $message, tree: $tree, parents: [$parent]}' |
		gh api --method POST "repos/${REPOSITORY}/git/commits" --input -)
	commit_oid=$(jq -er .sha <<<"$response")
	commit_url=$(jq -er .html_url <<<"$response")

	jq -e '.verification.verified == true and .verification.reason == "valid"' \
		<<<"$response" >/dev/null

	gh api --method PATCH "repos/${REPOSITORY}/git/refs/heads/${BRANCH}" \
		-f sha="$commit_oid" \
		-F force=false \
		>/dev/null

	git fetch "$remote_url" "$BRANCH"
	git update-ref HEAD "$commit_oid" "$local_head"

	cleanup
	trap - EXIT

	echo "Created verified commit: ${commit_url}"
fi

if [ -n "$TAG" ]; then
	tag_message=${TAG_MESSAGE:-Release ${TAG}}
	tag_oid=$(gh api \
		--method POST \
		"repos/${REPOSITORY}/git/tags" \
		-f tag="$TAG" \
		-f message="$tag_message" \
		-f object="$(git rev-parse HEAD)" \
		-f type=commit \
		--jq .sha)

	gh api \
		--method POST \
		"repos/${REPOSITORY}/git/refs" \
		-f ref="refs/tags/${TAG}" \
		-f sha="$tag_oid" \
		>/dev/null
fi
