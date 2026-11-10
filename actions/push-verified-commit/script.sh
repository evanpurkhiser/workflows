#!/usr/bin/env bash

set -euo pipefail

local_head=$(git rev-parse HEAD)
additions='[]'
deletions='[]'

while IFS= read -r -d '' status && IFS= read -r -d '' path; do
	if [ "$status" = D ]; then
		deletions=$(jq -c --arg path "$path" '. + [{path: $path}]' <<<"$deletions")
		continue
	fi

	mode=$(git ls-files --format='%(objectmode)' -- "$path")
	if [ "$mode" != 100644 ]; then
		echo "Unsupported Git mode ${mode} for ${path}" >&2
		exit 1
	fi

	contents=$(git show ":${path}" | base64 | tr -d '\n')
	additions=$(jq -c \
		--arg path "$path" \
		--arg contents "$contents" \
		'. + [{path: $path, contents: $contents}]' <<<"$additions")
done < <(git diff --cached --name-status --no-renames -z)

if [ "$additions" = '[]' ] && [ "$deletions" = '[]' ]; then
	echo "No changes to commit"
else
	headline=${COMMIT_MESSAGE%%$'\n'*}
	body=''

	if [[ "$COMMIT_MESSAGE" == *$'\n'* ]]; then
		body=${COMMIT_MESSAGE#*$'\n'}
	fi

	input=$(jq -n \
		--arg repository "$REPOSITORY" \
		--arg branch "$BRANCH" \
		--arg expectedHeadOid "$local_head" \
		--arg headline "$headline" \
		--arg body "$body" \
		--argjson additions "$additions" \
		--argjson deletions "$deletions" \
		'{
      branch: {
        repositoryNameWithOwner: $repository,
        branchName: $branch
      },
      expectedHeadOid: $expectedHeadOid,
      message: ({headline: $headline} + if $body == "" then {} else {body: $body} end),
      fileChanges: {
        additions: $additions,
        deletions: $deletions
      }
    }')

	response=$(jq -n \
		--arg query 'mutation($input: CreateCommitOnBranchInput!) { createCommitOnBranch(input: $input) { commit { oid url } } }' \
		--argjson input "$input" \
		'{query: $query, variables: {input: $input}}' |
		gh api graphql --input -)

	commit_oid=$(jq -er '.data.createCommitOnBranch.commit.oid' <<<"$response")
	commit_url=$(jq -er '.data.createCommitOnBranch.commit.url' <<<"$response")

	gh auth setup-git
	git fetch "${SERVER_URL}/${REPOSITORY}.git" "$BRANCH"
	git update-ref HEAD "$commit_oid" "$local_head"

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
