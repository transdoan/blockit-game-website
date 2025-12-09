/**
 * @file tilemap.d
 * @brief tile set and map data for levels
 *
 * parses level json, tracks inventory and spawn/goal, and draws tiles.
 */
module tilemap;

import std.json;
import std.file;
import std.algorithm;
import std.array;
import std.math;
import std.conv;
import std.string;
import std.range : enumerate;

import bindbc.sdl;

alias TextureLoader = SDL_Texture* delegate(string path);

alias JSONObject = JSONValue[string];
alias JSONArray = JSONValue[];

/// \enum TileBehavior
/// \brief extra behavior tags used by gameplay code
enum TileBehavior { 
    none, 
    lava, 
    rubber, 
    mud, 
    goal, 
    secret 
}

/// \struct TileDefinition
/// \brief description of a tile in the set
struct TileDefinition {
    string id;
    string name;
    dchar code;
    SDL_Color color;
    bool solid = false;
    TileBehavior behavior = TileBehavior.none;
    bool placeable = false;
    string inventoryKey;
    bool hidden = false;
    float speedMultiplier = 1.0f;
    float jumpMultiplier = 1.0f;
    string texturePath;
    SDL_Texture* texture = null;
}

/// \struct SurfaceInfo
/// \brief surface properties under or around the player
struct SurfaceInfo {
    bool onMud = false;
    bool onRubber = false;
    bool onLava = false;
    bool atGoal = false;
    bool onSecret = false;
}

/// \class TileSet
/// \brief holds tile definitions and simple lookup tables
class TileSet {
private:
    TileDefinition[] mDefinitions;
    int[string] mIdToIndex;
    int[dchar] mCodeToIndex;
    string[] mPlaceableOrder;
    dchar mEmptyCode = '.';
    string mEmptyId = "empty";
    int mEmptyIndex = -1;
public:
    /// default tile size in pixels
    int tileSize = 32;

    /// load tile definitions from a json file
    void LoadFromFile(string path){
        if (!exists(path)){
            return;
        }
        auto data = parseJSON(readText(path));
        LoadFromJSON(data);
    }

    /// fill internal tables from a json object
    void LoadFromJSON(JSONValue data){
        mDefinitions.length = 0;
        mIdToIndex.clear();
        mCodeToIndex.clear();
        mPlaceableOrder.length = 0;
        if ("tileSize" in data){
            tileSize = cast(int)data["tileSize"].integer;
        }
        if (!("tiles" in data)){
            return;
        }
        foreach (entry; data["tiles"].array){
            TileDefinition def;
            def.id = getString(entry, "id");
            def.name = getString(entry, "name", def.id);
            string codeStr = getString(entry, "code", def.id);
            def.code = codeStr.length > 0 ? codeStr[0] : def.id[0];
            def.color = parseColor(entry);
            def.solid = getBool(entry, "solid", false);
            def.placeable = getBool(entry, "placeable", false);
            def.inventoryKey = getString(entry, "inventory", def.id);
            def.hidden = getBool(entry, "hidden", false);
            def.behavior = parseBehavior(getString(entry, "behavior", "none"));
            def.speedMultiplier = getFloat(entry, "speedMultiplier", 1.0f);
            def.jumpMultiplier = getFloat(entry, "jumpBoost", 1.0f);
            def.texturePath = getString(entry, "texture");
            def.texture = null;
            int idx = cast(int)mDefinitions.length;
            mDefinitions ~= def;
            mIdToIndex[def.id] = idx;
            mCodeToIndex[def.code] = idx;
            if (def.placeable){
                mPlaceableOrder ~= def.id;
            }
            if (def.id == "empty"){
                mEmptyCode = def.code;
                mEmptyId = def.id;
                mEmptyIndex = idx;
            }
        }
    }

    /// find a tile definition by id
    TileDefinition* GetById(string id){
        if (id in mIdToIndex){
            return &mDefinitions[mIdToIndex[id]];
        }
        return null;
    }

    /// find a tile definition by ascii code
    TileDefinition* GetByCode(dchar code){
        if (code in mCodeToIndex){
            return &mDefinitions[mCodeToIndex[code]];
        }
        return null;
    }

    /// code used to represent empty tiles in the grid
    dchar EmptyCode(){
        return mEmptyCode;
    }

    /// default palette order for editors and players
    string[] DefaultPalette(){
        return mPlaceableOrder.dup;
    }

    /// id used when a grid cell is empty
    string EmptyId(){
        return mEmptyId;
    }

    /// pointer to the empty tile definition
    TileDefinition* EmptyTile(){
        if (mEmptyIndex >= 0 && mEmptyIndex < mDefinitions.length){
            return &mDefinitions[mEmptyIndex];
        }
        return null;
    }

    /// all ids in insertion order
    string[] AllTileIds(){
        string[] ids;
        foreach (def; mDefinitions){
            ids ~= def.id;
        }
        return ids;
    }
}

/// \class TileMap
/// \brief level grid, inventory, markers, and render helpers
class TileMap {
private:
    TileSet mTileSet;
    int mWidth = 0;
    int mHeight = 0;
    int mTileSize = 32;
    dchar[] mGrid;
    int mSpawnX = 0;
    int mSpawnY = 0;
    int mGoalX = 0;
    int mGoalY = 0;
    string[] mPalette;
    int[string] mInventory;
    string mTitle = "";
    string mId = "";
    TextureLoader mTextureLoader;

public:
    /// build a map from a tile set
    this(TileSet set){
        mTileSet = set;
        if (set !is null){
            mTileSize = set.tileSize;
        }
    }

    /// assign a callback to load textures on demand
    void SetTextureLoader(TextureLoader loader){
        mTextureLoader = loader;
    }

    /// read map layout, spawn/goal, inventory, and palette from json
    void LoadFromJSON(JSONValue data){
        mId = getString(data, "id");
        mTitle = getString(data, "title", mId);
        mWidth = cast(int)data["width"].integer;
        mHeight = cast(int)data["height"].integer;
        if ("tileSize" in data){
            mTileSize = cast(int)data["tileSize"].integer;
        } else if (mTileSet !is null){
            mTileSize = mTileSet.tileSize;
        }
        mGrid.length = mWidth * mHeight;
        auto rows = data["grid"].array;
        foreach (size_t y, JSONValue rowValue; rows){
            string row = rowValue.str;
            foreach (x; 0 .. mWidth){
                dchar code = (row.length > x) ? row[x] : (mTileSet !is null ? mTileSet.EmptyCode() : '.');
                size_t idx = y * mWidth + x;
                if (idx < mGrid.length){
                    mGrid[idx] = code;
                }
            }
        }
        dchar emptyCode = (mTileSet !is null) ? mTileSet.EmptyCode() : '.';
        foreach (i; 0 .. mGrid.length){
            if (mGrid[i] == '\0'){
                mGrid[i] = emptyCode;
            }
        }
        auto spawnArr = data["spawn"].array;
        if (spawnArr.length >= 2){
            mSpawnX = cast(int)spawnArr[0].integer;
            mSpawnY = cast(int)spawnArr[1].integer;
        }
        if ("goal" in data){
            auto goalArr = data["goal"].array;
            if (goalArr.length >= 2){
                mGoalX = cast(int)goalArr[0].integer;
                mGoalY = cast(int)goalArr[1].integer;
            }
        }
        mInventory = int[string].init;
        if ("inventory" in data){
            foreach (key, val; data["inventory"].object){
                mInventory[key] = cast(int)val.integer;
            }
        }
        mPalette = [];
        if ("palette" in data){
            foreach (entry; data["palette"].array){
                mPalette ~= entry.str;
            }
        } else if (mTileSet !is null){
            mPalette = mTileSet.DefaultPalette();
        }
        RebuildDerivedData();
    }

    /// write the current map to a json file
    bool Save(string path){
        auto obj = JSONValue(JSONObject.init);
        obj["id"] = JSONValue(mId);
        obj["title"] = JSONValue(mTitle);
        obj["width"] = JSONValue(mWidth);
        obj["height"] = JSONValue(mHeight);
        obj["tileSize"] = JSONValue(mTileSize);
        auto spawnArr = JSONArray.init;
        spawnArr ~= JSONValue(mSpawnX);
        spawnArr ~= JSONValue(mSpawnY);
        obj["spawn"] = JSONValue(spawnArr);
        auto goalArr = JSONArray.init;
        goalArr ~= JSONValue(mGoalX);
        goalArr ~= JSONValue(mGoalY);
        obj["goal"] = JSONValue(goalArr);
        auto inventoryObj = JSONObject.init;
        foreach (key, value; mInventory){
            inventoryObj[key] = JSONValue(value);
        }
        obj["inventory"] = JSONValue(inventoryObj);
        auto paletteArr = JSONArray.init;
        foreach (id; mPalette){
            paletteArr ~= JSONValue(id);
        }
        obj["palette"] = JSONValue(paletteArr);
        auto gridArr = JSONArray.init;
        foreach (y; 0 .. mHeight){
            auto rowChars = new char[mWidth];
            foreach (x; 0 .. mWidth){
                rowChars[x] = cast(char)mGrid[y * mWidth + x];
            }
            string row = rowChars.idup;
            gridArr ~= JSONValue(row);
        }
        obj["grid"] = JSONValue(gridArr);
        try {
            write(path, obj.toString());
            return true;
        } catch (Exception){
            return false;
        }
    }

    /// number of tiles in x
    int Width()
    {
        return mWidth;
    }

    /// number of tiles in y
    int Height()
    {
        return mHeight;
    }

    /// tile size in pixels
    int TileSize()
    {
        return mTileSize;
    }

    /// human readable level title
    string Title()
    {
        return mTitle;
    }

    /// set the level title
    void SetTitle(string title){
        mTitle = title;
    }

    /// copy of the palette order
    string[] Palette()
    {
        return mPalette.dup;
    }

    /// copy of the inventory counts
    int[string] Inventory()
    {
        return mInventory.dup;
    }

    /// set inventory count for a single tile id
    void SetInventoryCount(string id, int count){
        if (count < 0) count = 0;
        mInventory[id] = count;
    }

    /// current inventory count for a tile id
    int GetInventoryCount(string id){
        if (id in mInventory){
            return mInventory[id];
        }
        return 0;
    }

    /// access the underlying tile set
    TileSet Tiles()
    {
        return mTileSet;
    }

    /// spawn tile x index
    int SpawnTileX()
    {
        return mSpawnX;
    }

    /// spawn tile y index
    int SpawnTileY()
    {
        return mSpawnY;
    }

    /// goal tile x index
    int GoalTileX()
    {
        return mGoalX;
    }

    /// goal tile y index
    int GoalTileY()
    {
        return mGoalY;
    }

    /// true if tile coordinates are inside the grid
    bool InBounds(int tx, int ty){
        return tx >= 0 && ty >= 0 && tx < mWidth && ty < mHeight;
    }

    /// tile definition pointer at a tile coordinate
    TileDefinition* TileAt(int tx, int ty){
        if (!InBounds(tx, ty)){
            return null;
        }
        size_t idx = ty * mWidth + tx;
        if (idx >= mGrid.length){
            return null;
        }
        dchar code = mGrid[idx];
        if (mTileSet is null){
            return null;
        }
        return mTileSet.GetByCode(code);
    }

    /// tile definition pointer at a world coordinate
    TileDefinition* TileAtWorld(float wx, float wy){
        int tx = cast(int)floor(wx / mTileSize);
        int ty = cast(int)floor(wy / mTileSize);
        return TileAt(tx, ty);
    }

    /// set a tile id at grid coordinates
    bool SetTile(int tx, int ty, string id){
        if (!InBounds(tx, ty) || mTileSet is null){
            return false;
        }
        auto def = mTileSet.GetById(id);
        if (def is null){
            return false;
        }
        size_t idx = ty * mWidth + tx;
        if (idx >= mGrid.length){
            return false;
        }
        mGrid[idx] = def.code;
        RebuildDerivedData();
        return true;
    }

    /// clear a tile to empty at grid coordinates
    bool ClearTile(int tx, int ty){
        if (!InBounds(tx, ty) || mTileSet is null){
            return false;
        }
        size_t idx = ty * mWidth + tx;
        if (idx >= mGrid.length){
            return false;
        }
        mGrid[idx] = mTileSet.EmptyCode();
        RebuildDerivedData();
        return true;
    }

    /// set spawn marker for the player
    void SetSpawn(int tx, int ty){
        if (InBounds(tx, ty)){
            mSpawnX = tx;
            mSpawnY = ty;
        }
    }

    /// set goal marker for the level
    void SetGoal(int tx, int ty){
        if (InBounds(tx, ty)){
            mGoalX = tx;
            mGoalY = ty;
        }
    }

    /// true if the rect overlaps any solid tile (with a small pad)
    bool RectHitsSolid(SDL_FRect rect){
        if (mTileSet is null){
            return false;
        }
        int minX = cast(int)floor(rect.x / mTileSize);
        int maxX = cast(int)floor((rect.x + rect.w - 0.1f) / mTileSize);
        int minY = cast(int)floor(rect.y / mTileSize);
        int maxY = cast(int)floor((rect.y + rect.h - 0.1f) / mTileSize);
        foreach (ty; minY .. maxY + 1){
            foreach (tx; minX .. maxX + 1){
                if (tx < 0 || ty < 0){
                    return true;
                }
                if (ty >= mHeight){
                    continue;
                }
                if (tx >= mWidth){
                    return true;
                }
                auto tile = TileAt(tx, ty);
                if (tile !is null && tile.solid){
                    return true;
                }
            }
        }
        return false;
    }

    /// sample tile behavior around a rect and build surface info
    SurfaceInfo SurfaceInfoFor(SDL_FRect rect){
        SurfaceInfo info;
        int minX = cast(int)floor(rect.x / mTileSize);
        int maxX = cast(int)floor((rect.x + rect.w - 0.1f) / mTileSize);
        int minY = cast(int)floor(rect.y / mTileSize);
        int maxY = cast(int)floor((rect.y + rect.h - 0.1f) / mTileSize);
        
        foreach (ty; minY .. maxY + 1){
            foreach (tx; minX .. maxX + 1){
                auto tile = TileAt(tx, ty);
                if (tile is null){
                    continue;
                }
                switch (tile.behavior){
                    case TileBehavior.lava: info.onLava = true; break;
                    case TileBehavior.mud: info.onMud = true; break;
                    case TileBehavior.rubber: info.onRubber = true; break;
                    case TileBehavior.goal: info.atGoal = true; break;
                    case TileBehavior.secret: info.onSecret = true; break;
                    default: break;
                }
            }
        }
        
        float playerBottom = rect.y + rect.h;
        int belowTileY = cast(int)floor(playerBottom / mTileSize);
        for (int tx = minX; tx <= maxX; tx++){
            auto belowTile = TileAt(tx, belowTileY);
            if (belowTile !is null){
                switch (belowTile.behavior){
                    case TileBehavior.mud: info.onMud = true; break;
                    case TileBehavior.rubber: info.onRubber = true; break;
                    case TileBehavior.secret: info.onSecret = true; break;
                    default: break;
                }
            }
        }
        belowTileY++;
        for (int tx = minX; tx <= maxX; tx++){
            auto belowTile = TileAt(tx, belowTileY);
            if (belowTile !is null){
                switch (belowTile.behavior){
                    case TileBehavior.mud: info.onMud = true; break;
                    case TileBehavior.rubber: info.onRubber = true; break;
                    case TileBehavior.secret: info.onSecret = true; break;
                    default: break;
                }
            }
        }
        
        int leftTileX = cast(int)floor((rect.x - 0.1f) / mTileSize);
        for (int ty = minY; ty <= maxY; ty++){
            auto leftTile = TileAt(leftTileX, ty);
            if (leftTile !is null && leftTile.behavior == TileBehavior.secret){
                info.onSecret = true;
                break;
            }
        }
        
        int rightTileX = cast(int)floor((rect.x + rect.w + 0.1f) / mTileSize);
        for (int ty = minY; ty <= maxY; ty++){
            auto rightTile = TileAt(rightTileX, ty);
            if (rightTile !is null && rightTile.behavior == TileBehavior.secret){
                info.onSecret = true;
                break;
            }
        }
        
        int topTileY = cast(int)floor((rect.y - 0.1f) / mTileSize);
        for (int tx = minX; tx <= maxX; tx++){
            auto topTile = TileAt(tx, topTileY);
            if (topTile !is null && topTile.behavior == TileBehavior.secret){
                info.onSecret = true;
                break;
            }
        }
        
        return info;
    }

    /// true if a tile is within a given number of tiles from the player
    bool WithinPlacementRange(int tx, int ty, SDL_FRect playerRect, int tiles){
        int px = cast(int)floor((playerRect.x + playerRect.w * 0.5f) / mTileSize);
        int py = cast(int)floor((playerRect.y + playerRect.h * 0.5f) / mTileSize);
        return abs(px - tx) <= tiles && abs(py - ty) <= tiles;
    }

    /// draw visible tiles, optional grid, hover highlight, and markers
    void Render(SDL_Renderer* renderer, float camX, float camY, int viewW, int viewH, bool revealSecrets, bool drawGrid = false, bool highlightMarkers = true, int hoverX = -1, int hoverY = -1){
        if (mTileSet is null){
            return;
        }
        int minX = cast(int)floor(camX / mTileSize);
        int maxX = cast(int)ceil((camX + viewW) / mTileSize);
        int minY = cast(int)floor(camY / mTileSize);
        int maxY = cast(int)ceil((camY + viewH) / mTileSize);
        foreach (ty; minY .. maxY){
            foreach (tx; minX .. maxX){
                bool outX = tx < 0 || tx >= mWidth;
                bool outY = ty < 0 || ty >= mHeight;
                TileDefinition* tile = null;
                if (!outX && !outY){
                    tile = TileAt(tx, ty);
                }
                if (tile is null){
                    continue;
                }
                if (tile.id == "empty" || tile.code == '.'){
                    continue;
                }
                if (tile.texture is null && tile.texturePath.length > 0 && mTextureLoader !is null){
                    tile.texture = mTextureLoader(tile.texturePath);
                }
                SDL_FRect rect;
                rect.x = tx * mTileSize - camX;
                rect.y = ty * mTileSize - camY;
                rect.w = mTileSize;
                rect.h = mTileSize;
                bool hideSecret = tile.behavior == TileBehavior.secret && tile.hidden && !revealSecrets;
                if (tile.texture !is null){
                    SDL_RenderTexture(renderer, tile.texture, null, &rect);
                    if (hideSecret){
                        SDL_SetRenderDrawColor(renderer, 0, 0, 0, 180);
                        SDL_RenderFillRect(renderer, &rect);
                    }
                } else {
                    SDL_Color col = tile.color;
                    if (hideSecret){
                        col.a = 60;
                    }
                    SDL_SetRenderDrawColor(renderer, col.r, col.g, col.b, col.a);
                    SDL_RenderFillRect(renderer, &rect);
                }
            }
        }
        if (drawGrid){
            SDL_SetRenderDrawColor(renderer, 40, 40, 46, 160);

            int gridMaxX = mWidth;
            int gridMaxY = mHeight;
            
            foreach (x; minX .. gridMaxX + 1){
                SDL_FRect line;
                line.x = x * mTileSize - camX;
                line.y = 0 - camY;
                line.w = 1;
                line.h = mHeight * mTileSize;
                
                if (line.x >= -line.w && line.x < viewW && x <= mWidth){
                     SDL_RenderFillRect(renderer, &line);
                }
            }
            foreach (y; minY .. gridMaxY + 1){
                SDL_FRect line;
                line.x = 0 - camX;
                line.y = y * mTileSize - camY;
                line.w = mWidth * mTileSize;
                line.h = 1;
                
                if (line.y >= -line.h && line.y < viewH && y <= mHeight){
                    SDL_RenderFillRect(renderer, &line);
                }
            }
        }
        if (hoverX >= 0 && hoverY >= 0 && hoverX >= minX && hoverX < maxX && hoverY >= minY && hoverY < maxY){
            SDL_SetRenderDrawColor(renderer, 255, 255, 255, 80);
            SDL_FRect rect;
            rect.x = hoverX * mTileSize - camX;
            rect.y = hoverY * mTileSize - camY;
            rect.w = mTileSize;
            rect.h = mTileSize;
            SDL_RenderFillRect(renderer, &rect);
        }
        if (highlightMarkers){
            SDL_FRect spawnRect;
            spawnRect.x = mSpawnX * mTileSize - camX;
            spawnRect.y = mSpawnY * mTileSize - camY;
            spawnRect.w = mTileSize;
            spawnRect.h = mTileSize;
            SDL_Color spawnCol;
            spawnCol.r = 80; spawnCol.g = 220; spawnCol.b = 255; spawnCol.a = 200;
            drawOutline(renderer, spawnRect, spawnCol);
            SDL_FRect goalRect;
            goalRect.x = mGoalX * mTileSize - camX;
            goalRect.y = mGoalY * mTileSize - camY;
            goalRect.w = mTileSize;
            goalRect.h = mTileSize;
            SDL_Color goalCol;
            goalCol.r = 255; goalCol.g = 210; goalCol.b = 60; goalCol.a = 200;
            drawOutline(renderer, goalRect, goalCol);
        }
    }

    /// world width in pixels
    int WorldWidth(){ return mWidth * mTileSize; }
    /// world height in pixels
    int WorldHeight(){ return mHeight * mTileSize; }
    /// rectangle used for spawning the player
    SDL_FRect SpawnRect(){
        SDL_FRect rect;
        rect.x = mSpawnX * mTileSize + mTileSize * 0.2f;
        rect.y = mSpawnY * mTileSize;
        rect.w = mTileSize * 0.6f;
        rect.h = mTileSize * 0.9f;
        return rect;
    }
    /// rectangle used to mark the goal
    SDL_FRect GoalRect(){
        SDL_FRect rect;
        rect.x = mGoalX * mTileSize;
        rect.y = mGoalY * mTileSize;
        rect.w = mTileSize;
        rect.h = mTileSize;
        return rect;
    }

private:
    /// rebuild derived data such as goal indices
    void RebuildDerivedData(){
        foreach (ty; 0 .. mHeight){
            foreach (tx; 0 .. mWidth){
                auto tile = TileAt(tx, ty);
                if (tile is null){
                    continue;
                }
                if (tile.behavior == TileBehavior.goal){
                    mGoalX = tx;
                    mGoalY = ty;
                }
            }
        }
    }
}

    /// convert a string from json into a TileBehavior value
private TileBehavior parseBehavior(string value){
    string lower = value.toLower();
    if (lower == "lava") return TileBehavior.lava;
    if (lower == "rubber") return TileBehavior.rubber;
    if (lower == "mud") return TileBehavior.mud;
    if (lower == "goal") return TileBehavior.goal;
    if (lower == "secret") return TileBehavior.secret;
    return TileBehavior.none;
}

/// read a color array from json or return white
private SDL_Color parseColor(JSONValue entry){
    if (!("color" in entry)){
        return SDL_Color(255, 255, 255, 255);
    }
    auto arr = entry["color"].array;
    ubyte r = arr.length > 0 ? cast(ubyte)arr[0].integer : 255;
    ubyte g = arr.length > 1 ? cast(ubyte)arr[1].integer : 255;
    ubyte b = arr.length > 2 ? cast(ubyte)arr[2].integer : 255;
    ubyte a = arr.length > 3 ? cast(ubyte)arr[3].integer : 255;
    return SDL_Color(r, g, b, a);
}

/// get a string or number from a json object as text
private string getString(JSONValue entry, string key, string defaultValue = ""){
    if (key in entry.object){
        auto val = entry.object[key];
        if (val.type == JSONType.string){
            return val.str;
        }
        if (val.type == JSONType.integer){
            return to!string(val.integer);
        }
        if (val.type == JSONType.float_){
            return to!string(val.floating);
        }
    }
    return defaultValue;
}

/// get a bool-like value from json with a default
private bool getBool(JSONValue entry, string key, bool defaultValue){
    if (key in entry.object){
        auto val = entry.object[key];
        if (val.type == JSONType.true_) return true;
        if (val.type == JSONType.false_) return false;
        if (val.type == JSONType.integer) return val.integer != 0;
    }
    return defaultValue;
}

/// get a float value from json with a default
private float getFloat(JSONValue entry, string key, float defaultValue){
    if (key in entry.object){
        auto val = entry.object[key];
        if (val.type == JSONType.integer){
            return cast(float)val.integer;
        }
        if (val.type == JSONType.float_){
            return cast(float)val.floating;
        }
    }
    return defaultValue;
}

/// draw a simple rectangle outline used for spawn/goal markers
private void drawOutline(SDL_Renderer* renderer, SDL_FRect rect, SDL_Color color){
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_FRect top = rect;
    top.h = 2;
    SDL_RenderFillRect(renderer, &top);
    SDL_FRect bottom = rect;
    bottom.y = rect.y + rect.h - 2;
    bottom.h = 2;
    SDL_RenderFillRect(renderer, &bottom);
    SDL_FRect left = rect;
    left.w = 2;
    SDL_RenderFillRect(renderer, &left);
    SDL_FRect right = rect;
    right.x = rect.x + rect.w - 2;
    right.w = 2;
    SDL_RenderFillRect(renderer, &right);
}
