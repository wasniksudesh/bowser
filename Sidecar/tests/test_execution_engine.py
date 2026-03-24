"""
Tests: Execution Engine  (DataPacket, FanOutEngine, FanInEngine)

Feature: OpenClaw fan-out / fan-in runtime
Coverage:
  1. DataPacket constructors + introspection helpers
  2. FanOutEngine with 3 items, 1 executor failure -> 2 OK + 1 FAILED RowSet
  3. FanInEngine._combine_row_set_values in all three formats

Pure unit tests — no HTTP, no LLM.
"""

import pytest
from app.models.agent_schemas import (
    DataPacket,
    RowSet,
    RowResult,
    RowStatus,
    PlanStepModel,
    ForeachDirective,
    FanInDirective,
    ContextArtifactModel,
    Skill,
)
from app.services.execution_engine import FanOutEngine, FanInEngine


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_skill(skill_id="test.noop") -> Skill:
    async def _execute(params, auth):
        return DataPacket(rows=[{"result": "ok"}])

    return Skill(
        skill_id=skill_id,
        name="Noop",
        description="Does nothing",
        plugin_id="test",
        input_schema={},
        output_schema={},
        output_type="text",
        execute=_execute,
        domains=["test"],
        verbs=["noop"],
        nouns=["thing"],
        output_types=["text"],
    )


def _make_source_rowset(items: list[str], step_id="step0", field="val") -> RowSet:
    return RowSet(
        step_id=step_id,
        field=field,
        count=len(items),
        rows=[
            RowResult(
                index=i,
                value=DataPacket(rows=[{field: v}]),
                error=None,
                status=RowStatus.OK,
            )
            for i, v in enumerate(items)
        ],
    )


# ---------------------------------------------------------------------------
# Test 1 – DataPacket constructors + introspection
# ---------------------------------------------------------------------------

@pytest.mark.engine
def test_datapacket_constructors_and_introspection():
    """
    DataPacket.text(), DataPacket.error(), is_error(), first(), column()
    all behave correctly.
    """
    # text constructor
    tp = DataPacket.text("hello world")
    assert not tp.is_error()
    assert tp.first("text") == "hello world"
    assert tp.column("text") == ["hello world"]

    # error constructor
    ep = DataPacket.error("something broke", code="AUTH_ERROR", details={"x": 1})
    assert ep.is_error()
    assert ep.first("code") == "AUTH_ERROR"
    assert ep.first("error") == "something broke"

    # empty DataPacket is not an error
    empty = DataPacket(rows=[])
    assert not empty.is_error()
    assert empty.first("x") is None
    assert empty.column("x") == []


# ---------------------------------------------------------------------------
# Test 2 – FanOutEngine: partial failure
# ---------------------------------------------------------------------------

@pytest.mark.engine
async def test_fanout_partial_failure_produces_correct_rowset():
    """
    FanOutEngine with 3 items, executor fails on item at index 1.
    Result RowSet: 2 OK rows + 1 FAILED row.
    """
    engine = FanOutEngine()
    skill = _make_skill()
    source = _make_source_rowset(["a", "b", "c"])

    step = PlanStepModel(
        step_id="processItems",
        agent_type="operation",
        skill_id="test.noop",
        description="Process each item",
        input_mappings={"item": "{{ val }}"},
        foreach=ForeachDirective(
            source="step0.val",
            as_name="val",
            concurrency=1,
        ),
    )

    base_context = ContextArtifactModel(
        version=1,
        user_values={},
        step_outputs={},
        auth={},
    )

    call_count = 0

    async def executor(sk, ctx):
        nonlocal call_count
        call_count += 1
        if call_count == 2:
            raise RuntimeError("Simulated failure on item 1")
        return DataPacket(rows=[{"result": "ok"}])

    result = await engine.execute_fan_out(step, source, skill, base_context, executor)

    assert result.count == 3
    ok_rows = [r for r in result.rows if r.status == RowStatus.OK]
    failed_rows = [r for r in result.rows if r.status == RowStatus.FAILED]
    assert len(ok_rows) == 2
    assert len(failed_rows) == 1
    assert failed_rows[0].error is not None


# ---------------------------------------------------------------------------
# Test 3 – FanInEngine: all three combine formats
# ---------------------------------------------------------------------------

@pytest.mark.engine
def test_fanin_combine_formats():
    """
    FanInEngine._combine_row_set_values returns correct types for
    'array', 'structured', and 'concatenated' formats.
    """
    engine = FanInEngine()
    rowset = RowSet(
        step_id="getResults",
        field="score",
        count=3,
        rows=[
            RowResult(
                index=0,
                value=DataPacket(rows=[{"score": "90", "name": "Alice"}]),
                error=None,
                status=RowStatus.OK,
            ),
            RowResult(
                index=1,
                value=DataPacket(rows=[{"score": "85", "name": "Bob"}]),
                error=None,
                status=RowStatus.OK,
            ),
            RowResult(
                index=2,
                value=DataPacket(rows=[{"score": "78", "name": "Carol"}]),
                error=None,
                status=RowStatus.OK,
            ),
        ],
    )

    # array format
    arr = engine._combine_row_set_values(rowset, "score", "array")
    assert isinstance(arr, list)
    assert len(arr) == 3
    assert "90" in arr and "85" in arr and "78" in arr

    # structured format
    struct = engine._combine_row_set_values(rowset, "score", "structured")
    assert isinstance(struct, dict)
    assert struct["count"] == 3
    assert len(struct["items"]) == 3

    # concatenated format
    concat = engine._combine_row_set_values(rowset, "score", "concatenated")
    assert isinstance(concat, str)
    assert "90" in concat
    assert "85" in concat
    assert "78" in concat
