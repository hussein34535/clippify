from tool_registry import TOOL_REGISTRY, TOOL_CATEGORIES, count_tools, list_tools_by_category


def test_count_matches_header():
    total = count_tools()
    assert total == 215, f"Expected 215 tools, got {total}"


def test_categories_match_tool_counts():
    for cat, label in TOOL_CATEGORIES.items():
        tools = list_tools_by_category(cat)
        count_in_label = int(label.split("(")[1].split(" ")[0])
        assert len(tools) == count_in_label, (
            f"Category '{cat}' has {len(tools)} tools but label says {count_in_label}"
        )


def test_all_tools_have_required_fields():
    for name, tool in TOOL_REGISTRY.items():
        assert "description" in tool, f"Tool '{name}' missing description"
        assert "category" in tool, f"Tool '{name}' missing category"
        assert "params" in tool, f"Tool '{name}' missing params"
        assert "requires_confirmation" in tool, f"Tool '{name}' missing requires_confirmation"
