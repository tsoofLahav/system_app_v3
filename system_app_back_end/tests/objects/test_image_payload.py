from areas.objects.services.image_payload import mirrored, panes_of


def test_panes_of_single_url():
    assert panes_of({"url": "/a.png", "caption": "A"}) == [
        {"url": "/a.png", "caption": "A"}
    ]


def test_panes_of_images_list():
    payload = {
        "url": "/a.png",
        "caption": "A",
        "images": [
            {"url": "/a.png", "caption": "A"},
            {"url": "/b.png", "caption": "B"},
        ],
    }
    assert panes_of(payload)[1]["url"] == "/b.png"


def test_mirrored_keeps_first_on_url():
    out = mirrored(
        [{"url": "/a.png", "caption": "A"}, {"url": "/b.png", "caption": "B"}],
        width=0.5,
        look="frame",
    )
    assert out["url"] == "/a.png"
    assert out["caption"] == "A"
    assert out["width"] == 0.5
    assert out["look"] == "frame"
    assert len(out["images"]) == 2
