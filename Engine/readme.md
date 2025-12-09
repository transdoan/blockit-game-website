
## Game/Engine Publicity

**Project Website**: *TODO*: *please edit the project website with a link here and also at the root directory of the READMD.md*

### Engine Architecture Diagram

![Engine Architecture Diagram](../media/diagram.png)

## Compilation Instructions

*Please edit if there are any special build instructions beyond running `dub`*

Just run `dub` in the `PSET/Engine` folder.

## Add any additional notes here

*your additional notes, or things ULA/TF/Instructors should know*

## Project Hieararchy

In the future, other engineers may take a look at your project, so I would recommend to keep it organized given the following requirements below. Forming some good organization habits now will help us later on when our project grows as well. These are the required files you should have 

### ./Engine Directory Organization

- Game
    - The folder where your game specific code goes demonstrating your engine (or perhaps if you have multiple games to showcase, one folder per game).
- Docs 
    - Source Code Documentation
- Assets
    - Art assets (With the Sub directories music, sound, images, and anything else)
- 'source' or 'src'
    - source code(.d files) The make file or any build scripts that automate the building of your project should reside here.
- include
    - header files(.di files if needed, or any C header files if you used importC)
- lib
    - libraries (.so, .dll, .a, .dylib files). Note this is a good place to put SDL if you are doing a static build
- bin
    - This is the directory where your built executable(.exe for windows, .app for Mac, or a.out for Linux) and any additional generated files are put after each build.
- EngineBuild (Optional)
    - You may optionally put a .zip to you final deliverable. One should be able to copy and paste this directory, and only this directory onto another machine and be able to run the game. This is optional because for this course we will be building your projects from source. However, in the game industry it is useful to always have a build of a game ready for testers, thus a game project hieararchy would likely have this directory in a repo or other storage medium.
- ThirdParty
    - Code that you have not written if any. 

**Note: For the final project you may add additional directories if you like, for example for your game which demonstrates your engine works.** 

**Additional Notes:** 

1. src and include should only contain ".d" or ".di" files. Why? It makes it very fast to do a backup of your game project as one example. Secondly, binary files that are generated often clutter up directories. I should not see any binaries in your repository, you may use a '.gitignore' file to help prevent this automatically. 

Post-Mortem

Although we are quite proud of the end product of our engine, we encountered many setbacks when coding. Apart from the inevitable scheduling difficulties, the maze of brainstorming, and the temptation to keep adding features, the major setback was the constant cycle of debugging. We spent a lot of time with minor tweaking, trying to get the movements of the knight to feel good, the size of the tiles to be perfect, and the other game objects to have a noticeable purpose. These small adjustments added up quickly, and we often found ourselves revisiting earlier decisions to maintain consistency across the entire project.

If given an additional eight weeks to work on this project, the first major improvement we would focus on is organizing the codebase. The coding ended up becoming a little bloated, especially as we continued adding mechanics late into development. This affected the scalability of the end product and made certain systems harder to modify cleanly. Given more time, we would like to streamline the code to make it more efficient, readable, and easier to build upon for future iterations.

We would also like to add more functionality into the engine. We have so many ideas that we were not able to implement. There is so much content that we could add if given more time. This includes more levels, but also new things like audio, water spaces, moving dangers, puzzles, checkpoints, or even PvP and co-op game modes. Another idea is to be able to save multiple levels and send them to your friends as a challenge. With more time and polish, this engine could grow into a much more flexible and fully realized creative tool.
