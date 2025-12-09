/**
 * @file app.d
 * @brief program entry point
 *
 * starts the taa game maker application and runs the main loop.
 */
module app;

import gameapplication;

/// simple entry point that owns the game application
void main()
{
    auto app = new GameApplication("TAA Game Maker");
    scope (exit) {
        if (app !is null) {
            destroy(app);
        }
    }
    app.Run();
}
