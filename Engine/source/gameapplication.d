/**
 * @file gameapplication.d
 * @brief main application and game loop
 *
 * handles window creation, the sdl renderer, scenes, and the main loop.
 */
module gameapplication;

import std.string;
import std.file : exists;

import bindbc.sdl;

import sdl_abstraction;
import resourcemanager;
import scenes;

/// \class GameApplication
/// \brief wraps the core engine loop and scene management
class GameApplication {
private:
    SDL_Window* mWindow = null;
    SDL_Renderer* mRenderer = null;
    ResourceManager mResources;
    MenuScene mMenu;
    PlayScene mPlay;
    EditorScene mEditor;
    SceneBase mScene;
    bool mRunning = true;
    long mPerfFreq;
    long mLastPerf;
    enum WindowWidth = 960;
    enum WindowHeight = 600;
public:
    /// create the window, renderer, resource manager, and initial scenes
    this(string title){
        mWindow = SDL_CreateWindow(title.toStringz, WindowWidth, WindowHeight, SDL_WINDOW_RESIZABLE);
        mRenderer = SDL_CreateRenderer(mWindow, null);
        mPerfFreq = cast(long)SDL_GetPerformanceFrequency();
        mLastPerf = cast(long)SDL_GetPerformanceCounter();
        mResources = new ResourceManager(mRenderer);
        if (exists("game.json")){
            mResources.LoadResourcesFromJSON("game.json");
        }
        mMenu = new MenuScene(mResources, WindowWidth, WindowHeight);
        mPlay = new PlayScene(mResources, WindowWidth, WindowHeight);
        mEditor = new EditorScene(mResources, WindowWidth, WindowHeight);
        mScene = mMenu;
        if (mScene !is null){
            mScene.OnEnter();
        }
    }

    /// clean up scenes and sdl objects
    ~this(){
        if (mEditor !is null){ mEditor.OnExit(); }
        if (mPlay !is null){ mPlay.OnExit(); }
        if (mMenu !is null){ mMenu.OnExit(); }
        if (mRenderer !is null){
            SDL_DestroyRenderer(mRenderer);
            mRenderer = null;
        }
        if (mWindow !is null){
            SDL_DestroyWindow(mWindow);
            mWindow = null;
        }
    }

    /// run the main loop until the user quits
    void Run(){
        SDL_Event e;
        while (mRunning){
            while (SDL_PollEvent(&e)){
                if (e.type == SDL_EVENT_QUIT){
                    mRunning = false;
                } else if (mScene !is null){
                    mScene.HandleEvent(e);
                }
            }
            long now = cast(long)SDL_GetPerformanceCounter();
            float dt = cast(float)(now - mLastPerf) / cast(float)mPerfFreq;
            mLastPerf = now;
            if (dt > 0.1f){
                dt = 0.1f;
            }
            if (mScene !is null){
                mScene.Input();
                mScene.Update(dt);
                mScene.Render(mRenderer);
                SDL_RenderPresent(mRenderer);
                auto req = mScene.ConsumeRequest();
                HandleSwitch(req);
            } else {
                SDL_Delay(16);
            }
            
            long frameEnd = cast(long)SDL_GetPerformanceCounter();
            float frameTime = cast(float)(frameEnd - now) / cast(float)mPerfFreq;
            float targetFrameTime = 1.0f / 60.0f;
            if (frameTime < targetFrameTime){
                uint delayMs = cast(uint)((targetFrameTime - frameTime) * 1000.0f);
                if (delayMs > 0){
                    SDL_Delay(delayMs);
                }
            }
        }
    }

private:
    /// handle a scene change request from the active scene
    void HandleSwitch(SceneRequest req){
        if (!req.pending){
            return;
        }
        if (req.target == "menu"){
            SwitchTo(mMenu);
        } else if (req.target == "play"){
            string levelId = req.payload;
            if (levelId.length == 0){
                auto levels = mResources.Levels();
                if (levels.length > 0){
                    levelId = levels[0].id;
                }
            }
            if (levelId.length > 0 && mPlay.LoadLevel(levelId)){
                SwitchTo(mPlay);
            }
        } else if (req.target == "editor"){
            SwitchTo(mEditor);
        } else if (req.target == "quit"){
            mRunning = false;
        }
    }

    /// leave the current scene and enter a new one
    void SwitchTo(SceneBase scene){
        if (mScene !is null){
            mScene.OnExit();
        }
        mScene = scene;
        if (mScene !is null){
            mScene.OnEnter();
        }
    }
}
