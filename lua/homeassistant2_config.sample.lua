return {
    settings = {
        url = "http://192.168.10.12:8123",
        token = "YOUR_LONG_LIVED_ACCESS_TOKEN",
        show_getting_started = true,
    },
    user_actions = {
        {
            label = "\u{EA2D} All Lights OFF",
            action = "light.turn_off",
            action_data = {
                entity_id = "all",
            },
        },
        {
            label = "\u{E3E2} Evening Lighting",
            action = "light.turn_on",
            action_data = {
                area_id = { "living_room", "bedroom" },
                label_id = "ambient_lights",
                brightness_pct = 30,
                rgb_color = { 255, 100, 25 },
                transition = 5,
            },
        },
        {
            label = "\u{E20A} Heat Living Room to 22°C",
            action = "climate.set_temperature",
            action_data = {
                entity_id = "climate.living_room",
                hvac_mode = "heat",
                temperature = 22,
            },
        },
        {
            label = "\u{F0DC} Set Desk Height to 80cm",
            action = "number.set_value",
            action_data = {
                entity_id = "number.upsy_desky_target_desk_height",
                value = 80,
            },
        },
    },
}
