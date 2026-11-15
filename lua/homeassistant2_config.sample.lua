return {
    ["settings"] = {
        ["show_getting_started"] = true,
        ["token"] = "YOUR_LONG_LIVED_ACCESS_TOKEN",
        ["url"] = "http://192.168.10.12:8123",
    },
    ["user_actions"] = {
        {
            ["meta"] = {
                ["label"] = "Living Room Lights",
                ["action"] = "light.turn_on",
            },
            ["entity_id"] = "all",
            ["brightness_pct"] = 80,
            ["transition"] = 2,
        },
        {
            ["meta"] = {
                ["label"] = "Bedroom Lights",
                ["action"] = "light.turn_off",
            },
            ["area_id"] = "bedroom",
        },
        {
            ["meta"] = {
                ["label"] = "Evening Lighting",
                ["action"] = "light.turn_on",
            },
            ["area_id"] = { "living_room", "bedroom" },
            ["label_id"] = "ambient_lights",
            ["brightness_pct"] = 30,
            ["color_temp_kelvin"] = 2700,
            ["transition"] = 5,
        },
    },
}
