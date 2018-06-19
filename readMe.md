## Sinfool

This repository contains all the needed resourced for creating a "[Sinfool Repo](https://www.reddit.com/r/jailbreak/comments/6ui9ro/release_sinfool_repo_redone_from_the_ground_up/)".

### File and Folder overview

- **code** (directory): Contains the code run to update the Sandbox folder and list.html file

- **Sandbox** (directory): Contains all the Theos projects to create the debs for every patch. This should be uploaded to the website for users to look at. A Tweak.xm and Tweak.mm file is included for every project. The .mm is compiled, becuase it's faster, and the .xm is included for viewing purposes

- **Sandbox#** (directory): The Sandbox folder is split up into a certain amount of working folders. The amount is based on how many logical CPU cores your device has. These are gone through and compiled by the bash scripts

- **patches** (directory): Contains all of the Flex patches. The patches are saved by their cloudID. The code to save new patches is not included in this repo. FlexToTheos would need to be modified to get this information.

- **debs** (directory): The debs outputted by Theos. Should be uploaded to the server in the same directory as `list.html` and `Sandbox`

- **failed.txt**: The projects that failed to build. This file is created by the bash scripts

- **list.html**: The file that should be uploaded to the server next to the `debs` and `Sandbox` directories. 

- **runEach.sh** and **theosSet.sh**: Bash scripts that asynchronously compile all of the Theos projects in `Sandbox#`. Only call `./runEach.sh` with no arguments. `theosSet.sh` is called by runEach.sh and should not be called manually


### How to Use

The main code is written in Objective-C, so needs to be run on macOS, or iOS (compile with Theos instead of Xcode). 

After running the code in the `code` directory, run the `./runEach.sh` script. The number inside may need to be changed; it current says `while ((m < 8))`. If the greatest Sandbox folder is `Sandbox3`, for example, that should be `while ((m < 4))`. This can be automated, I just didn't feel like it. 

`./runEach.sh` will exit within a second. It's asynchronous though, so multiple tasks will be forked into the background. On my 8 core machine, it takes about half an hour to compile all of the projects. If you'd like, it would be cool to optimize not having to compile every project over again. I haven't done that, because I was changing the main code a lot, and wanted to re-compile everything with the latest changes. 

After you think all the projects are done compiling (I usually check Activity Monitor), run the code in `code` again. This will update `list.html` with the appropriate info given the updated `failed.txt` 

Lastly, upload `list.html`, `Sandbox`, and `debs` to the server into the same directory. 
