/**
 * @file resourcemanager.d
 * @brief small loader for textures, sounds, animations, tiles, and levels
 *
 * reads game.json and keeps shared pointers to loaded data.
 */
module resourcemanager;

import std.stdio;
import std.string;
import std.json;
import std.file;
import std.algorithm;
import std.conv : to;
import bindbc.sdl;
import tilemap;

/// description of a level from the game config
struct LevelEntry {
    string id;
    string title;
    string file;
    string description;
}

/// \class ResourceManager
/// \brief loads and owns all shared runtime resources
class ResourceManager {
    private SDL_Renderer* mRenderer;
    private SDL_Texture*[string] mTextures;
    private SDL_AudioStream*[string] mSounds;
    private ubyte*[string] mSoundBuffers;
    private uint[string] mSoundLengths;
    private SDL_AudioSpec*[string] mSoundSpecs;
    private JSONValue[string] mAnimationData;
    private SDL_AudioDeviceID mAudioDevice;
    private TileSet mTileSet;
    private LevelEntry[] mLevels;
    private string mEditorDefault;
    private string mEditorSave;
    
    /// create a manager bound to a renderer and audio device
    this(SDL_Renderer* renderer){
        mRenderer = renderer;
        
        SDL_AudioSpec desired;
        desired.freq = 44100;
        desired.format = SDL_AUDIO_S16;
        desired.channels = 2;
        
        mAudioDevice = SDL_OpenAudioDevice(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &desired);
    }
    
    /// release any textures, audio streams, and the audio device
    ~this(){
        foreach (name, texture; mTextures){
            if (texture !is null){
                SDL_DestroyTexture(texture);
            }
        }
        foreach (name, stream; mSounds){
            if (stream !is null){
                SDL_DestroyAudioStream(stream);
            }
        }
        foreach (name, buffer; mSoundBuffers){
            if (buffer !is null){
                SDL_free(buffer);
            }
        }
        foreach (name, spec; mSoundSpecs){
            if (spec !is null){
                SDL_free(spec);
            }
        }
        if (mAudioDevice != 0){
            SDL_CloseAudioDevice(mAudioDevice);
        }
    }
    
    /// load a bmp texture once and cache it by name
    SDL_Texture* LoadTexture(string filepath, string name = ""){
        if (name.length == 0){
            name = filepath;
        }
        if (name in mTextures){
            return mTextures[name];
        }
        import std.string : toStringz;
        SDL_Surface* surface = SDL_LoadBMP(filepath.toStringz);
        
        import std.algorithm : canFind;
        if (filepath.canFind("ice.bmp")){
             SDL_SetSurfaceColorKey(surface, true, SDL_MapSurfaceRGB(surface, 0, 0, 0));
             writeln("INFO: Loading ice.bmp with black color key");
        } else {
             SDL_SetSurfaceColorKey(surface, true, SDL_MapSurfaceRGB(surface, 255, 0, 255));
        }
        
        SDL_Texture* texture = SDL_CreateTextureFromSurface(mRenderer, surface);
        SDL_DestroySurface(surface);
        if (texture !is null){
            mTextures[name] = texture;
        } else {
            writeln("ERROR: CreateTextureFromSurface failed for: ", filepath);
        }
        return texture;
    }
    
    /// get a previously loaded texture or null
    SDL_Texture* GetTexture(string name){
        if (name in mTextures){
            return mTextures[name];
        }
        return null;
    }
    
    /// load a wav file into memory and prepare a stream
    void LoadSound(string filepath, string name = ""){
        if (name.length == 0){
            name = filepath;
        }
        if (name in mSounds){
            return;
        }
        SDL_AudioSpec* spec = new SDL_AudioSpec();
        ubyte* buffer;
        uint length;
        if (SDL_LoadWAV(filepath.toStringz, spec, &buffer, &length)){
            mSoundSpecs[name] = spec;
            mSoundBuffers[name] = buffer;
            mSoundLengths[name] = length;
            mSounds[name] = SDL_CreateAudioStream(spec, spec);
        }
    }
    
    /// queue a loaded sound on the shared audio device
    void PlaySound(string name){
        if (name in mSounds && name in mSoundBuffers){
            auto stream = mSounds[name];
            auto buffer = mSoundBuffers[name];
            auto len = mSoundLengths[name];
            SDL_PutAudioStreamData(stream, buffer, cast(int)len);
            SDL_ResumeAudioDevice(mAudioDevice);
        }
    }
    
    /// read an animation json file and keep the raw data
    void LoadAnimationData(string filepath, string name){
        if (!exists(filepath)){
            return;
        }
        auto content = readText(filepath);
        auto json = parseJSON(content);
        mAnimationData[name] = json;
    }
    
    /// get raw animation json by id
    JSONValue GetAnimationData(string name){
        if (name in mAnimationData){
            return mAnimationData[name];
        }
        return JSONValue(null);
    }
    
    /// read game.json and load textures, sounds, tiles, and level list
    void LoadResourcesFromJSON(string filepath){
        string content = readText(filepath);
        JSONValue config = parseJSON(content);
        
        if ("resources" in config){
            JSONValue resources = config["resources"];
            
            if ("textures" in resources){
                foreach (name, path; resources["textures"].object){
                    LoadTexture(path.str, name);
                }
            }
            
            if ("animations" in resources){
                foreach (name, path; resources["animations"].object){
                    LoadAnimationData(path.str, name);
                }
            }
            
            if ("sounds" in resources){
                foreach (name, path; resources["sounds"].object){
                    LoadSound(path.str, name);
                }
            }

            if ("tiles" in resources){
                auto tilesObj = resources["tiles"];
                if ("definitions" in tilesObj){
                    auto defPath = tilesObj["definitions"].str;
                    mTileSet = new TileSet();
                    mTileSet.LoadFromFile(defPath);
                }
            }

            if ("levels" in resources){
                mLevels.length = 0;
                foreach (entry; resources["levels"].array){
                    LevelEntry info;
                    info.id = getString(entry, "id");
                    info.title = getString(entry, "title", info.id);
                    info.file = getString(entry, "file");
                    info.description = getString(entry, "description");
                    if (info.id.length && info.file.length){
                        mLevels ~= info;
                    }
                }
            }

            if ("editor" in resources){
                auto editorObj = resources["editor"];
                if ("defaultFile" in editorObj){
                    mEditorDefault = editorObj["defaultFile"].str;
                }
                if ("saveFile" in editorObj){
                    mEditorSave = editorObj["saveFile"].str;
                }
            }
        }
        
        if (mEditorSave.length > 0 && exists(mEditorSave)) {
            bool exists = false;
            foreach(level; mLevels) {
                if (level.file == mEditorSave) {
                    exists = true;
                    break;
                }
            }
            
            if (!exists) {
                try {
                    auto customData = parseJSON(readText(mEditorSave));
                    LevelEntry customLevel;
                    customLevel.id = "custom_level";
                    customLevel.file = mEditorSave;
                    customLevel.title = getString(customData, "title", "Custom Level");
                    customLevel.description = "User created level";
                    mLevels ~= customLevel;
                } catch (Exception e) {
                    // failed to load custom level metadata, skip it
                }
            }
        }
    }

    /// get the loaded tile set
    TileSet Tiles(){
        return mTileSet;
    }

    /// copy the list of known levels
    LevelEntry[] Levels(){
        return mLevels.dup;
    }

    /// find a level entry by id or return null
    LevelEntry* FindLevel(string id){
        foreach (i, entry; mLevels){
            if (entry.id == id){
                return &mLevels[i];
            }
        }
        return null;
    }

    /// load a level json file directly from disk
    JSONValue LoadLevelJSON(string path){
        if (!exists(path)){
            return JSONValue(null);
        }
        return parseJSON(readText(path));
    }

    /// default file the editor should open
    string EditorDefaultFile(){
        if (mEditorDefault.length){
            return mEditorDefault;
        }
        if (mLevels.length > 0){
            return mLevels[0].file;
        }
        return "";
    }

    /// path where the editor saves custom levels
    string EditorSavePath(){
        if (mEditorSave.length){
            return mEditorSave;
        }
        return "Game/Scenes/custom_level.json";
    }

private:
    /// helper to get a value from a json object with a default
    string getString(JSONValue entry, string key, string defaultValue = ""){
        if (key in entry.object){
            auto val = entry.object[key];
            if (val.type == JSONType.string){
                return val.str;
            }
            if (val.type == JSONType.integer){
                return to!string(val.integer);
            }
        }
        return defaultValue;
    }
}
