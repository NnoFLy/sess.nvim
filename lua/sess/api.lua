return {
    commands = require("sess.commands"),
    get = {
        current = require("sess.state").get_current_session,
        prev = require("sess.state").get_prev_session,
        all = require("sess.session").get.all,
        by_name = require("sess.session").get.by_name,
        by_path = require("sess.session").get.by_path,
    },
}
