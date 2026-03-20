"""
GitHub Plugin - V1
Provides skills for interacting with GitHub repositories
"""

from typing import Any, Dict
from app.models.agent_schemas import Plugin, Skill, AuthRequirement, AuthStrategy, DataPacket


# =============================================================================
# Executor Functions
# =============================================================================

async def _list_commits(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    List commits from a GitHub repository
    
    Returns:
        DataPacket with schema {"sha", "message", "author", "date", "commit_shas"}
    """
    try:
        from github import Github
        print(f"[SSW] ListCommits {params}")
        token = auth.get("github_token", "")
        if not token:
            return DataPacket.error("github_token is required in auth context", code="AUTH_ERROR")
        
        g = Github(token)
        repo = g.get_repo(params["repo"])
        branch = params.get("branch", "main")
        limit = params.get("limit", 10)
        
        # Ensure limit is an integer
        try:
            limit = int(limit)
        except (ValueError, TypeError):
            limit = 10
        
        commits = list(repo.get_commits(sha=branch)[:limit])
        
        # Extract commit SHAs for chaining
        commit_shas = [c.sha for c in commits]
        
        # Build rows with all data
        rows = [
            {
                "sha": c.sha[:8],
                "message": c.commit.message.split('\n')[0][:80],
                "author": c.commit.author.name if c.commit.author else "Unknown",
                "date": str(c.commit.author.date) if c.commit.author else "",
                "commit_shas": commit_shas
            }
            for c in commits
        ]
        
        return DataPacket(
            schema_def={
                "sha": "string",
                "message": "string",
                "author": "string",
                "date": "string",
                "commit_shas": "array"
            },
            rows=rows
        )
    except Exception as e:
        return DataPacket.error(str(e), code="GITHUB_ERROR", details={"repo": params.get("repo")})


async def _get_commit_diff(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    Get diff for a specific commit
    
    Returns:
        DataPacket with text content
    """
    try:
        from github import Github
        print(f"[SSW] GetCommitDiff {params}")

        token = auth.get("github_token", "")
        if not token:
            return DataPacket.error("github_token is required in auth context", code="AUTH_ERROR")
        
        g = Github(token)
        repo = g.get_repo(params["repo"])
        commit = repo.get_commit(params["commit_sha"])
        diff_text = []
        files_changed = []
        for file in commit.files:
            files_changed.append(file.filename)
            # diff_text.append(f"File: {file.filename}")
            # diff_text.append(f"Status: {file.status}")
            # diff_text.append(f"Changes: +{file.additions} -{file.deletions}")
            if file.patch:
                diff_text.append(file.patch)
            diff_text.append("")
        
        diff_result = "\n".join(diff_text)
        
        return DataPacket(
            schema_def={"diff_text": "string", "files_changed": "array"},
            rows=[{
                "diff_text": diff_result,
                "files_changed": files_changed
            }]
        )
    except Exception as e:
        return DataPacket.error(str(e), code="GITHUB_ERROR", details={"commit_sha": params.get("commit_sha")})


async def _list_prs(params: Dict[str, Any], auth: Dict[str, Any]) -> DataPacket:
    """
    List pull requests from a GitHub repository
    
    Returns:
        DataPacket with PR data
    """
    try:
        from github import Github
        
        token = auth.get("github_token", "")
        if not token:
            return DataPacket.error("github_token is required in auth context", code="AUTH_ERROR")
        
        g = Github(token)
        repo = g.get_repo(params["repo"])
        state = params.get("state", "open")
        limit = params.get("limit", 10)
        
        # Ensure limit is an integer
        try:
            limit = int(limit)
        except (ValueError, TypeError):
            limit = 10
        
        prs = list(repo.get_pulls(state=state)[:limit])
        
        # Extract PR numbers for chaining
        pr_numbers = [pr.number for pr in prs]
        
        rows = [
            {
                "number": str(pr.number),
                "title": pr.title[:80],
                "author": pr.user.login if pr.user else "Unknown",
                "state": pr.state,
                "created": str(pr.created_at),
                "pr_numbers": pr_numbers,
                "pull_requests": [{"number": p.number, "title": p.title} for p in prs]
            }
            for pr in prs
        ]
        
        return DataPacket(
            schema_def={
                "number": "string",
                "title": "string",
                "author": "string",
                "state": "string",
                "created": "string",
                "pr_numbers": "array",
                "pull_requests": "array"
            },
            rows=rows
        )
    except Exception as e:
        return DataPacket.error(str(e), code="GITHUB_ERROR", details={"repo": params.get("repo")})


def get_github_plugin() -> Plugin:
    """
    Returns the GitHub plugin with all skills
    """
    return Plugin(
        plugin_id="github",
        name="GitHub Plugin",
        version="1.0.0",
        description="Skills for interacting with GitHub repositories",
        auth_requirements=[
            AuthRequirement(
                auth_id="github_auth",
                description="GitHub authentication for API access",
                strategies=[
                    AuthStrategy(
                        type="token",
                        context_key="github_token",
                        description="Personal access token with repo scope"
                    ),
                    AuthStrategy(
                        type="user_password",
                        context_key="github_credentials",
                        description="GitHub username and password"
                    )
                ]
            )
        ],
        skills=[
            # Skill 1: List Commits
            Skill(
                skill_id="listCommits",
                name="List Commits",
                description="List recent commits from a GitHub repository",
                input_schema={
                    "type": "object",
                    "properties": {
                        "repo": {
                            "type": "string",
                            "description": "Repository in format 'owner/repo'"
                        },
                        "branch": {
                            "type": "string",
                            "description": "Branch name (default: main)",
                            "default": "main"
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Number of commits to retrieve (default: 10)",
                            "default": 10
                        }
                    },
                    "required": ["repo"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "commit_shas": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Array of all commit SHAs"
                        }
                    }
                },
                output_type="table",
                execution_type="sdk",
                execute=_list_commits,
                domains=["github", "version-control", "git", "code"],
                verbs=["list", "get", "fetch", "show"],
                nouns=["commits", "commit", "history", "changes"],
                output_types=["table", "list"]
            ),
            
            # Skill 2: Get Commit Diff
            Skill(
                skill_id="getCommitDiff",
                name="Get Commit Diff",
                description="Retrieve the diff/changes for a specific commit",
                input_schema={
                    "type": "object",
                    "properties": {
                        "repo": {
                            "type": "string",
                            "description": "Repository in format 'owner/repo'"
                        },
                        "commit_sha": {
                            "type": "string",
                            "description": "Commit SHA to retrieve diff for"
                        }
                    },
                    "required": ["repo"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "diff_text": {
                            "type": "string",
                            "description": "The full diff text"
                        },
                        "files_changed": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "List of files changed in the commit"
                        }
                    }
                },
                output_type="text",
                execution_type="sdk",
                execute=_get_commit_diff,
                domains=["github", "version-control", "git", "code"],
                verbs=["get", "fetch", "show", "retrieve"],
                nouns=["diff", "changes", "commit", "patch"],
                output_types=["text", "textBlock"]
            ),
            
            # Skill 3: List Pull Requests
            Skill(
                skill_id="listPRs",
                name="List Pull Requests",
                description="List pull requests from a GitHub repository",
                input_schema={
                    "type": "object",
                    "properties": {
                        "repo": {
                            "type": "string",
                            "description": "Repository in format 'owner/repo'"
                        },
                        "state": {
                            "type": "string",
                            "description": "PR state: open, closed, or all (default: open)",
                            "enum": ["open", "closed", "all"],
                            "default": "open"
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Number of PRs to retrieve (default: 10)",
                            "default": 10
                        }
                    },
                    "required": ["repo"]
                },
                output_schema={
                    "type": "object",
                    "properties": {
                        "pr_numbers": {
                            "type": "array",
                            "items": {"type": "integer"},
                            "description": "Array of PR numbers"
                        },
                        "pull_requests": {
                            "type": "array",
                            "items": {"type": "object"},
                            "description": "Array of pull request objects with number and title"
                        }
                    }
                },
                output_type="table",
                execution_type="sdk",
                execute=_list_prs,
                domains=["github", "version-control", "code"],
                verbs=["list", "get", "fetch", "show"],
                nouns=["pull-requests", "prs", "pr", "pull request"],
                output_types=["table", "list"]
            )
        ]
    )
