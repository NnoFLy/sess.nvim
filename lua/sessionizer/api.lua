return {
    commands = require("sessionizer.commands"),
    get = {
        current = require("sessionizer.state").get_current_session,
        prev = require("sessionizer.state").get_prev_session,
        all = require("sessionizer.session").get.all,
        by_name = require("sessionizer.session").get.by_name,
        by_path = require("sessionizer.session").get.by_path,
    },
}
