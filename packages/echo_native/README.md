# echo_native

In-repo Android plugin for Echo. It owns the buffer of notifications captured while the app isn't listening, plus the calendar query. Because it's a plugin, it's registered in every Flutter engine, which lets the background briefing alarm drain overnight notifications before generating.
