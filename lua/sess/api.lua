return {
    commands = require("sess.commands"),
    get = {
        current = require("sess.state").get_current_session,
        prev = require("sess.state").get_prev_session,
        all = require("sess.session").list,
        by_name = require("sess.session").get_by_name,
        by_path = require("sess.session").get_by_path,
        by_id = require("sess.session").get,
    },
}
