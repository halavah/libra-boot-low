#!/bin/bash

# Navigate to the repository root (parent of .github directory)
cd "$(dirname "$0")/.."

# Get current branch name
echo "Detecting current Git branch..."
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -z "$current_branch" ]; then
    echo "Failed to detect current Git branch."
    echo "Make sure you are in a Git repository."
    exit 1
fi
echo "Current branch: $current_branch"

# Stage all changes first
echo "Staging all changes..."
git add .
if [ $? -ne 0 ]; then
    echo "Failed to stage changes."
    exit 1
fi

# Check if there are changes to commit
git diff --staged --quiet
if [ $? -eq 0 ]; then
    echo "No changes to commit."

    # If no changes, just sync and exit
    echo "Syncing with origin/$current_branch (fetch + rebase)..."
    git fetch origin "$current_branch"
    git rebase "origin/$current_branch"
    exit 0
fi

# Commit changes with timestamped message
timestamp=$(date +"%Y%m%d_%H%M%S")
echo "Committing changes with timestamp: $timestamp..."
git commit -m "$timestamp"
if [ $? -ne 0 ]; then
    echo "Failed to commit changes."
    exit 1
fi

# Sync with the remote repository (fetch + rebase, immune to FETCH_HEAD races with IDE auto-fetch)
echo "Syncing with origin/$current_branch (fetch + rebase)..."
git fetch origin "$current_branch"
if [ $? -ne 0 ]; then
    echo "Failed to fetch changes."
    exit 1
fi
git rebase "origin/$current_branch"
if [ $? -ne 0 ]; then
    echo "Failed to rebase onto origin/$current_branch. Resolve conflicts, run 'git rebase --continue', then rerun the script."
    exit 1
fi

# Push changes to the repository
echo "Pushing changes to origin/$current_branch..."
git push origin "$current_branch"
if [ $? -ne 0 ]; then
    echo "Failed to push changes."
    exit 1
fi

echo "Changes successfully pulled, committed, and pushed to branch: $current_branch"
exit 0
