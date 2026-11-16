from pathlib import Path

def test_ea_source_exists():
    file = Path("Experts/JARA_GOLD_SPEED_SCALPER.mq5")
    assert file.exists()

def test_ea_source_not_empty():
    file = Path("Experts/JARA_GOLD_SPEED_SCALPER.mq5")
    assert file.stat().st_size > 0

def test_ea_has_required_functions():


    source = Path("Experts/JARA_GOLD_SPEED_SCALPER.mq5").read_text()
    assert "OnInit()" in source
    assert "OnTick()" in source
    assert "OnDeinit(" in source

