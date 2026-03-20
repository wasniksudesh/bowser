#!/usr/bin/env python3
"""
Integration test for DataPacket contract
Tests real skills + agent loop with mocked LLM responses
"""

import asyncio
from unittest.mock import MagicMock, patch
from app.models.agent_schemas import (
    DataPacket,
)
from app.services.plugins import get_github_plugin


async def test_datapacket_github_skill():
    """Test that GitHub skills return DataPacket"""
    print("\n=== Test 1: GitHub Skill Returns DataPacket ===")
    
    plugin = get_github_plugin()
    list_commits_skill = plugin.skills[0]
    
    # Mock params and auth
    params = {"repo": "test/repo", "branch": "main", "limit": 3}
    auth = {"github_token": "fake_token"}
    
    # Mock GitHub API
    with patch("github.Github") as mock_github:
        mock_repo = MagicMock()
        mock_commit = MagicMock()
        mock_commit.sha = "abc123"
        mock_commit.commit.message = "Test commit"
        mock_commit.commit.author.name = "Test Author"
        mock_commit.commit.author.date = "2024-01-01"
        
        mock_repo.get_commits.return_value = [mock_commit]
        mock_github.return_value.get_repo.return_value = mock_repo
        
        # Execute skill
        result = await list_commits_skill.execute(params, auth)
        
        # Verify result is DataPacket
        assert isinstance(result, DataPacket), f"Expected DataPacket, got {type(result)}"
        assert result.schema_def is not None, "Schema should be defined"
        assert len(result.rows) > 0, "Should have rows"
        assert "sha" in result.rows[0], "Row should have 'sha' field"
        assert "message" in result.rows[0], "Row should have 'message' field"
        
        print(f"✓ Skill returned DataPacket with {len(result.rows)} rows")
        print(f"✓ Schema: {list(result.schema_def.keys())}")
        print(f"✓ First row keys: {list(result.rows[0].keys())}")


async def test_datapacket_error_handling():
    """Test that skills return ErrorDataPacket on failure"""
    print("\n=== Test 2: Error Handling Returns ErrorDataPacket ===")
    
    plugin = get_github_plugin()
    list_commits_skill = plugin.skills[0]
    
    # Missing auth token
    params = {"repo": "test/repo"}
    auth = {}
    
    result = await list_commits_skill.execute(params, auth)
    
    # Verify error DataPacket
    assert isinstance(result, DataPacket), "Should return DataPacket"
    assert result.is_error(), "Should be error DataPacket"
    assert "error" in result.rows[0], "Should have error field"
    assert "code" in result.rows[0], "Should have code field"
    assert result.rows[0]["code"] == "AUTH_ERROR", "Should have AUTH_ERROR code"
    
    print(f"✓ Error returned as DataPacket")
    print(f"✓ Error message: {result.rows[0]['error']}")
    print(f"✓ Error code: {result.rows[0]['code']}")


async def test_observation_result_structure():
    """Test ObservationResult has correct DataPacket structure"""
    print("\n=== Test 3: ObservationResult Structure ===")
    
    from app.services.react_agent import ReactAgentLoop
    from app.services.skill_registry import get_registry
    
    # Register GitHub plugin
    registry = get_registry()
    registry.register_plugin(get_github_plugin())
    
    # Get the skill
    skill = registry.get_skill("github.listCommits")
    assert skill is not None, "Skill should be registered"
    
    # Mock GitHub API
    with patch("github.Github") as mock_github:
        mock_repo = MagicMock()
        mock_commit = MagicMock()
        mock_commit.sha = "abc123def456"
        mock_commit.commit.message = "Fix bug in DataPacket"
        mock_commit.commit.author.name = "Test Developer"
        mock_commit.commit.author.date = "2024-01-15"
        
        mock_repo.get_commits.return_value = [mock_commit, mock_commit, mock_commit]
        mock_github.return_value.get_repo.return_value = mock_repo
        
        # Create agent loop and test _create_observation
        loop = ReactAgentLoop()
        
        # Execute skill
        params = {"repo": "test/repo", "branch": "main", "limit": 3}
        auth = {"github_token": "fake_token"}
        data_packet = await skill.execute(params, auth)
        
        # Create observation
        observation = loop._create_observation("github.listCommits", skill, data_packet)
        
        # Verify observation structure
        assert observation.success == True, "Should be successful"
        assert observation.view == "table", f"Expected 'table' view, got {observation.view}"
        assert observation.data is not None, "Should have data"
        assert isinstance(observation.data, DataPacket), "Data should be DataPacket"
        assert len(observation.data.rows) == 3, f"Expected 3 rows, got {len(observation.data.rows)}"
        assert "context_updates" in observation.model_dump(), "Should have context_updates"
        
        print(f"✓ ObservationResult has correct structure")
        print(f"✓ View: {observation.view}")
        print(f"✓ DataPacket has {len(observation.data.rows)} rows")
        print(f"✓ Context updates: {list(observation.context_updates.keys())}")


async def test_text_skill_datapacket():
    """Test text-based skill returns proper DataPacket"""
    print("\n=== Test 4: Text Skill Returns DataPacket ===")
    
    from app.services.plugins import get_text_analysis_plugin
    
    plugin = get_text_analysis_plugin()
    compare_skill = plugin.skills[2]  # compare skill
    
    params = {
        "text1": "Hello world",
        "text2": "Hello world!",
        "mode": "similarity"
    }
    auth = {}
    
    result = await compare_skill.execute(params, auth)
    
    # Verify DataPacket
    assert isinstance(result, DataPacket), "Should return DataPacket"
    assert not result.is_error(), "Should not be error"
    assert "text" in result.rows[0], "Should have 'text' field"
    assert "Similarity:" in result.rows[0]["text"], "Should contain similarity result"
    
    print(f"✓ Text skill returned DataPacket")
    print(f"✓ Text content: {result.rows[0]['text'][:50]}...")


async def test_fan_out_source_resolution():
    """Test that fan-out can resolve source RowSet from context"""
    print("\n=== Test 5: Fan-Out Source RowSet Resolution ===")
    
    from app.services.react_agent import ReactAgentLoop
    from app.models.agent_schemas import (
        ContextArtifactModel,
        ContextValueModel,
        PlanStepModel,
        ForeachDirective,
        Skill
    )
    import json
    
    # Create agent loop
    loop = ReactAgentLoop()
    
    # Create context with commit_shas array
    commit_shas = [
        "abc123def456",
        "789ghi012jkl",
        "345mno678pqr"
    ]
    
    context = ContextArtifactModel(
        version=1,
        user_values={},
        step_outputs={
            "listCommits.commit_shas": ContextValueModel(
                name="commit_shas",
                description="List of commit SHAs",
                value=json.dumps(commit_shas),  # Stored as JSON string
                required=False,
                field_type="string"
            )
        },
        auth={}
    )
    
    # Test _resolve_source_row_set
    source_row_set = loop._resolve_source_row_set("listCommits", "commit_shas", context)
    
    # Verify RowSet was created
    assert source_row_set is not None, "Should resolve source RowSet"
    assert source_row_set.count == 3, f"Expected 3 rows, got {source_row_set.count}"
    assert len(source_row_set.rows) == 3, "Should have 3 rows"
    
    # Verify each row has DataPacket value
    for i, row in enumerate(source_row_set.rows):
        assert isinstance(row.value, DataPacket), f"Row {i} value should be DataPacket"
        assert row.value.rows, f"Row {i} DataPacket should have rows"
        assert "commit_shas" in row.value.rows[0], f"Row {i} should have 'commit_shas' field"
        assert row.value.rows[0]["commit_shas"] == commit_shas[i], f"Row {i} value mismatch"
    
    print(f"✓ Resolved RowSet with {source_row_set.count} rows")
    print(f"✓ Each row contains DataPacket with correct field")
    print(f"✓ Sample value: {source_row_set.rows[0].value.rows[0]}")


async def test_fan_out_template_resolution():
    """Test that fan-out templates resolve correctly from DataPacket"""
    print("\n=== Test 6: Fan-Out Template Resolution ===")
    
    from app.services.execution_engine import resolve_template
    from app.models.agent_schemas import DataPacket
    
    # Test 1: Single-field DataPacket with field access
    commit_sha = "abc123def456"
    item_packet = DataPacket(rows=[{"commit_shas": commit_sha}])
    
    # Resolve {{ sha }} template (wrong field name, should return scalar)
    result1 = resolve_template("{{ sha }}", "sha", commit_sha)
    assert result1 == commit_sha, f"Expected {commit_sha}, got {result1}"
    
    # Resolve {{ commit_shas }} from DataPacket
    result2 = resolve_template("{{ item }}", "item", item_packet)
    assert result2 == commit_sha, f"Expected {commit_sha}, got {result2}"
    
    # Test 2: Multi-field DataPacket with field access
    multi_packet = DataPacket(rows=[{
        "sha": "abc123",
        "message": "Test commit",
        "author": "Test Author"
    }])
    
    result3 = resolve_template("{{ commit.sha }}", "commit", multi_packet)
    assert result3 == "abc123", f"Expected 'abc123', got {result3}"
    
    result4 = resolve_template("{{ commit.message }}", "commit", multi_packet)
    assert result4 == "Test commit", f"Expected 'Test commit', got {result4}"
    
    # Test 3: Literal passthrough
    result5 = resolve_template("literal-value", "item", item_packet)
    assert result5 == "literal-value", f"Expected 'literal-value', got {result5}"
    
    print(f"✓ Single-field DataPacket resolves to scalar value")
    print(f"✓ Multi-field DataPacket supports field access")
    print(f"✓ Literal values pass through unchanged")


async def test_fan_out_execution():
    """Test full fan-out execution with mock skill"""
    print("\n=== Test 7: Fan-Out Execution ===")
    
    from app.services.execution_engine import FanOutEngine
    from app.models.agent_schemas import (
        PlanStepModel,
        ForeachDirective,
        Skill,
        RowSet,
        RowResult,
        RowStatus,
        ContextArtifactModel,
        DataPacket
    )
    
    # Create mock skill
    async def mock_execute(params, auth):
        return DataPacket(rows=[{"result": "OK"}])
    
    mock_skill = Skill(
        skill_id="test.processCommit",
        name="Process Commit",
        description="Process a single commit",
        plugin_id="test",
        input_schema={
            "type": "object",
            "properties": {
                "commit_sha": {"type": "string"}
            },
            "required": ["commit_sha"]
        },
        output_schema={
            "type": "object",
            "properties": {
                "result": {"type": "string"}
            }
        },
        output_type="text",
        execute=mock_execute,
        domains=["test"],
        verbs=["process"],
        nouns=["commit"],
        output_types=["text"]
    )
    
    # Create source RowSet with 3 commits
    source_row_set = RowSet(
        step_id="listCommits",
        field="commit_shas",
        count=3,
        rows=[
            RowResult(
                index=0,
                value=DataPacket(rows=[{"commit_shas": "abc123"}]),
                error=None,
                status=RowStatus.OK
            ),
            RowResult(
                index=1,
                value=DataPacket(rows=[{"commit_shas": "def456"}]),
                error=None,
                status=RowStatus.OK
            ),
            RowResult(
                index=2,
                value=DataPacket(rows=[{"commit_shas": "ghi789"}]),
                error=None,
                status=RowStatus.OK
            )
        ]
    )
    
    # Create plan step with foreach
    step = PlanStepModel(
        step_id="processCommits",
        agent_type="operation",
        skill_id="test.processCommit",
        description="Process each commit",
        input_mappings={"commit_sha": "{{ sha }}"},
        foreach=ForeachDirective(
            source="listCommits.commit_shas",
            as_name="sha",
            concurrency=2
        )
    )
    
    # Create base context
    base_context = ContextArtifactModel(
        version=1,
        user_values={},
        step_outputs={},
        auth={}
    )
    
    # Mock skill executor that returns DataPacket
    async def mock_skill_executor(skill, task_context):
        # Extract commit_sha from context
        commit_sha = task_context.user_values.get("commit_sha")
        if commit_sha:
            return DataPacket(rows=[{"result": f"Processed {commit_sha.value}"}])
        return DataPacket.error("Missing commit_sha", code="PARAM_ERROR")
    
    # Execute fan-out
    engine = FanOutEngine()
    result_row_set = await engine.execute_fan_out(
        step, source_row_set, mock_skill, base_context, mock_skill_executor
    )
    
    # Verify results
    assert result_row_set.count == 3, f"Expected 3 results, got {result_row_set.count}"
    assert len(result_row_set.rows) == 3, "Should have 3 result rows"
    
    ok_count = sum(1 for r in result_row_set.rows if r.status == RowStatus.OK)
    assert ok_count == 3, f"Expected 3 successful rows, got {ok_count}"
    
    # Verify each result is a DataPacket
    for i, row in enumerate(result_row_set.rows):
        assert isinstance(row.value, DataPacket), f"Row {i} should have DataPacket value"
        assert row.value.rows, f"Row {i} DataPacket should have rows"
        assert "result" in row.value.rows[0], f"Row {i} should have 'result' field"
    
    print(f"✓ Fan-out executed successfully with {result_row_set.count} items")
    print(f"✓ All {ok_count} items processed successfully")
    print(f"✓ Sample result: {result_row_set.rows[0].value.rows[0]}")


async def test_fan_in_aggregation():
    """Test fan-in aggregation of RowSet results"""
    print("\n=== Test 8: Fan-In Aggregation ===")
    
    from app.services.execution_engine import FanInEngine
    from app.models.agent_schemas import (
        PlanStepModel,
        FanInDirective,
        Skill,
        RowSet,
        RowResult,
        RowStatus,
        ContextArtifactModel,
        DataPacket
    )
    
    # Create a RowSet with multiple results
    row_set = RowSet(
        step_id="processCommits",
        field="commit_shas",
        count=3,
        rows=[
            RowResult(
                index=0,
                value=DataPacket(rows=[{
                    "sha": "abc123",
                    "lines_added": 10,
                    "lines_deleted": 5
                }]),
                error=None,
                status=RowStatus.OK
            ),
            RowResult(
                index=1,
                value=DataPacket(rows=[{
                    "sha": "def456",
                    "lines_added": 20,
                    "lines_deleted": 3
                }]),
                error=None,
                status=RowStatus.OK
            ),
            RowResult(
                index=2,
                value=DataPacket(rows=[{
                    "sha": "ghi789",
                    "lines_added": 15,
                    "lines_deleted": 8
                }]),
                error=None,
                status=RowStatus.OK
            )
        ]
    )
    
    # Test _combine_row_set_values with different formats
    engine = FanInEngine()
    
    # Test array format
    shas_array = engine._combine_row_set_values(row_set, "sha", "array")
    assert isinstance(shas_array, list), "Array format should return list"
    assert len(shas_array) == 3, f"Expected 3 SHAs, got {len(shas_array)}"
    assert "abc123" in shas_array, "Should contain 'abc123'"
    assert "def456" in shas_array, "Should contain 'def456'"
    assert "ghi789" in shas_array, "Should contain 'ghi789'"
    
    # Test structured format
    structured = engine._combine_row_set_values(row_set, "sha", "structured")
    assert isinstance(structured, dict), "Structured format should return dict"
    assert structured["count"] == 3, f"Expected count 3, got {structured['count']}"
    assert structured["total_rows"] == 3, f"Expected total_rows 3, got {structured['total_rows']}"
    assert len(structured["items"]) == 3, "Should have 3 items"
    
    # Test concatenated format
    lines_added_concat = engine._combine_row_set_values(row_set, "lines_added", "concatenated")
    assert isinstance(lines_added_concat, str), "Concatenated format should return string"
    assert "10" in lines_added_concat, "Should contain '10'"
    assert "20" in lines_added_concat, "Should contain '20'"
    assert "15" in lines_added_concat, "Should contain '15'"
    
    print(f"✓ Array format: {shas_array}")
    print(f"✓ Structured format: count={structured['count']}, items={len(structured['items'])}")
    print(f"✓ Concatenated format: {lines_added_concat[:50]}...")


async def test_fan_in_execution():
    """Test full fan-in execution with mock skill"""
    print("\n=== Test 9: Fan-In Execution ===")
    
    from app.services.execution_engine import FanInEngine
    from app.models.agent_schemas import (
        PlanStepModel,
        FanInDirective,
        Skill,
        RowSet,
        RowResult,
        RowStatus,
        ContextArtifactModel,
        DataPacket
    )
    
    # Create mock skill that summarizes commits
    async def mock_execute(params, auth):
        return DataPacket(rows=[{"summary": "OK"}])
    
    mock_skill = Skill(
        skill_id="test.summarizeCommits",
        name="Summarize Commits",
        description="Summarize all commits",
        plugin_id="test",
        input_schema={
            "type": "object",
            "properties": {
                "commits": {"type": "array"}
            }
        },
        output_schema={
            "type": "object",
            "properties": {
                "summary": {"type": "string"}
            }
        },
        output_type="text",
        execute=mock_execute,
        domains=["test"],
        verbs=["summarize"],
        nouns=["commits"],
        output_types=["text"]
    )
    
    # Create source RowSet with commit diffs
    source_row_set = RowSet(
        step_id="getCommitDiffs",
        field="diff",
        count=3,
        rows=[
            RowResult(
                index=0,
                value=DataPacket(rows=[{"diff": "diff for abc123"}]),
                error=None,
                status=RowStatus.OK
            ),
            RowResult(
                index=1,
                value=DataPacket(rows=[{"diff": "diff for def456"}]),
                error=None,
                status=RowStatus.OK
            ),
            RowResult(
                index=2,
                value=DataPacket(rows=[{"diff": "diff for ghi789"}]),
                error=None,
                status=RowStatus.OK
            )
        ]
    )
    
    # Create plan step with fanin
    step = PlanStepModel(
        step_id="summarizeAllCommits",
        agent_type="operation",
        skill_id="test.summarizeCommits",
        description="Summarize all commit diffs",
        input_mappings={"commits": "{{ combined }}"},
        fanin=FanInDirective(
            source="getCommitDiffs.diff",
            combine_field="diff",
            format="array"
        )
    )
    
    # Create base context
    base_context = ContextArtifactModel(
        version=1,
        user_values={},
        step_outputs={},
        auth={}
    )
    
    # Mock skill executor that receives combined data
    async def mock_skill_executor(skill, task_context):
        # Extract commits from context
        commits = task_context.user_values.get("commits")
        if commits:
            import json
            commits_list = json.loads(commits.value)
            return DataPacket(rows=[{
                "summary": f"Summarized {len(commits_list)} commits",
                "count": len(commits_list)
            }])
        return DataPacket.error("Missing commits", code="PARAM_ERROR")
    
    # Execute fan-in
    engine = FanInEngine()
    result_packet, updated_context = await engine.execute_fan_in(
        step, source_row_set, mock_skill, base_context, mock_skill_executor
    )
    
    # Verify result
    assert isinstance(result_packet, DataPacket), "Should return DataPacket"
    assert not result_packet.is_error(), "Should not be error"
    assert len(result_packet.rows) > 0, "Should have rows"
    assert "summary" in result_packet.rows[0], "Should have summary field"
    assert "count" in result_packet.rows[0], "Should have count field"
    assert result_packet.rows[0]["count"] == 3, f"Expected count 3, got {result_packet.rows[0]['count']}"
    
    print(f"✓ Fan-in executed successfully")
    print(f"✓ Result: {result_packet.rows[0]['summary']}")
    print(f"✓ Combined {result_packet.rows[0]['count']} items")


async def test_fan_out_error_handling():
    """Test fan-out handles partial failures correctly"""
    print("\n=== Test 10: Fan-Out Error Handling ===")
    
    from app.services.execution_engine import FanOutEngine
    from app.models.agent_schemas import (
        PlanStepModel,
        ForeachDirective,
        Skill,
        RowSet,
        RowResult,
        RowStatus,
        ContextArtifactModel,
        DataPacket
    )
    
    # Create mock skill
    async def mock_execute(params, auth):
        return DataPacket(rows=[{"result": "OK"}])
    
    mock_skill = Skill(
        skill_id="test.processCommit",
        name="Process Commit",
        description="Process a single commit",
        plugin_id="test",
        input_schema={},
        output_schema={},
        output_type="text",
        execute=mock_execute,
        domains=["test"],
        verbs=["process"],
        nouns=["commit"],
        output_types=["text"]
    )
    
    # Create source RowSet
    source_row_set = RowSet(
        step_id="listCommits",
        field="commit_shas",
        count=3,
        rows=[
            RowResult(index=0, value=DataPacket(rows=[{"sha": "abc123"}]), error=None, status=RowStatus.OK),
            RowResult(index=1, value=DataPacket(rows=[{"sha": "def456"}]), error=None, status=RowStatus.OK),
            RowResult(index=2, value=DataPacket(rows=[{"sha": "ghi789"}]), error=None, status=RowStatus.OK)
        ]
    )
    
    # Create plan step
    step = PlanStepModel(
        step_id="processCommits",
        agent_type="operation",
        skill_id="test.processCommit",
        description="Process commits",
        input_mappings={"commit_sha": "{{ sha.sha }}"},
        foreach=ForeachDirective(
            source="listCommits.commit_shas",
            as_name="sha",
            concurrency=2
        )
    )
    
    base_context = ContextArtifactModel(version=1, user_values={}, step_outputs={}, auth={})
    
    # Mock executor that fails on second item by raising exception
    call_count = 0
    async def failing_executor(skill, task_context):
        nonlocal call_count
        call_count += 1
        if call_count == 2:
            raise Exception("Simulated failure")
        commit_sha = task_context.user_values.get("commit_sha")
        return DataPacket(rows=[{"result": f"OK: {commit_sha.value if commit_sha else 'unknown'}"}])
    
    # Execute fan-out
    engine = FanOutEngine()
    result_row_set = await engine.execute_fan_out(
        step, source_row_set, mock_skill, base_context, failing_executor
    )
    
    # Verify mixed results
    assert result_row_set.count == 3, "Should have 3 results"
    
    ok_count = sum(1 for r in result_row_set.rows if r.status == RowStatus.OK)
    failed_count = sum(1 for r in result_row_set.rows if r.status == RowStatus.FAILED)
    
    assert ok_count == 2, f"Expected 2 successful, got {ok_count}"
    assert failed_count == 1, f"Expected 1 failed, got {failed_count}"
    
    # Verify failed row has error
    failed_row = next(r for r in result_row_set.rows if r.status == RowStatus.FAILED)
    assert failed_row.error is not None, "Failed row should have error message"
    
    print(f"✓ Fan-out handled partial failures: {ok_count} OK, {failed_count} failed")
    print(f"✓ Failed row error: {failed_row.error}")


async def main():
    """Run all tests"""
    print("=" * 60)
    print("DataPacket Integration Tests")
    print("=" * 60)
    
    try:
        await test_datapacket_github_skill()
        await test_datapacket_error_handling()
        await test_observation_result_structure()
        await test_text_skill_datapacket()
        await test_fan_out_source_resolution()
        await test_fan_out_template_resolution()
        await test_fan_out_execution()
        await test_fan_in_aggregation()
        await test_fan_in_execution()
        await test_fan_out_error_handling()
        
        print("\n" + "=" * 60)
        print("✓ ALL TESTS PASSED")
        print("=" * 60)
        return 0
    except Exception as e:
        print(f"\n✗ TEST FAILED: {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit_code = asyncio.run(main())
    exit(exit_code)
