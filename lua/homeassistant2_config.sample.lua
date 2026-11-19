return {
    settings = {
        url = "http://192.168.10.12:8123",
        token = "YOUR_LONG_LIVED_ACCESS_TOKEN",
        show_getting_started = true,
    },
    user_actions = {
        {
            label = "Living Room Lights",
            action = "light.turn_on",
            action_data = {
                entity_id = "all",
                brightness_pct = 80,
                transition = 2,
            },
        },
        {
            label = "Bedroom Lights",
            action = "light.turn_off",
            action_data = {
                area_id = "bedroom",
            },
        },
        {
            label = "Evening Lighting",
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
            label = "Play a Jellyfin Movie",
            action = "media_player.play_media",
            action_data = {
                entity_id = "media_player.living_room",
                media_content_id = "YOUR_JELLYFIN_MOVIE_ID",
                media_content_type = "movie",
            },
        },
    },
}