# BI wiki pages (captured 2026-10-27)

Raw text the user pasted from the Bohemia community wiki (https://community.bistudio.com/wiki).
Sections: Introduction to Arma Scripting, Getting Started, Category: Arma 3 Editing (index), Category: Eden Editor (index).

---

Introduction to Arma Scripting
Page
Discussion
Read
View source
View history
Categories: To-doArma Scripting Tutorials
Scripting is one of the most powerful and most versatile tools available in the Arma sandbox. Unfortunately, it is also one of the most complex and unforgiving aspects of addon (i.e. mod) and mission creation.

All Arma games from Arma: Cold War Assault to Arma 3 use a scripting language called SQF. Its predecessor SQS has been considered deprecated since Armed Assault (2006) and is no longer used. As of Arma Reforger (2022), SQF has been succeeded by Enforce Script. This document only considers SQF.



Scripting Topics
There is a plethora of topics to learn about in the context of Arma scripting (see the table below). Fortunately, there is no need to acquire detailed knowledge about all of these things in order to get started with scripting. To aid with prioritisation, this page provides three selections of topics, each relevant to beginner, intermediate and advanced scripters respectively.

Real Virtuality Scripting
Terminology	Argument ● Identifier ● Expression ● Operand ● Operators ● Parameter ● Statement ● Variables ● Magic Variables ● Function
Syntax	SQF Syntax ● SQS Syntax ● Order of Precedence ● Control Structures
Tutorials	Introduction to Arma Scripting ● Code Best Practices ● Example Code ● Code Optimisation ● Mission Optimisation ● Multiplayer Scripting ● SQS → SQF
Data Types	General	Array ● Boolean ● Code ● Config ● Control ● Diary Record ● Display ● Eden Entity ● Eden ID ● Editor Object ● Group ● HashMap ● Location ● Namespace ● Number ● Object ● Script Handle
Side ● String ● Structured Text ● Task ● Team ● Team Member ● NaN ● Anything ● Nothing ● Void ● Switch Type ● While Type ● With Type ● For Type ● If Type
Special Arrays	Array of Eden Entities ● Color ● Date ● ParticleArray ● Position ● Unit Loadout Array ● Vector3D ● Waypoint
Scripting Commands	Scripting Commands ● Scripting Commands by Functionality
Scripting Functions	Scripting Functions ● Functions by Functionality
Debugging	Common Scripting Errors ● Debugging Techniques ● Exception handling
Advanced	Event Scripts ● Event Handlers ● PreProcessor Commands ● Initialisation Order ● Performance Profiling


Beginner Scripting
🚧
TODO:
Using existing functions
Variables
Variables are a fundamental building block of scripting (and programming in general). Like in mathematics, they serve as placeholders for values. A few examples:

A = 1; The variable A now has the value 1.
B = 2; The variable B now has the value 2.
C = "Hello World!"; The variable C now has the value "Hello World!".
A variable always has a Data Type. In the example above, the variables A and B both have the data type Number, while C has the data type String. The data type of a variable is not fixed and changes automatically based on the current value of the variable.

Commands and Operators
Two other basic tools of scripting are commands and Operators. In fact, they are so basic that the examples in the Variables section above already had to make use of an operator: The equals sign (=) serves as the assignment operator, assigning values to variables. Similarly, symbols such as +, -, * and / are also operators. Using operators is quite simple:

A = 1.5;
B = -2 * A;
C = A + B + 3.5; // Result: C is 2
Commands are often more versatile and complex than operators and can sometimes be used to interact with the game in some way. For instance, the setPosATL command can be used to change the position of an object in the game world, the damage command returns the amount of damage an object has suffered and the systemChat command can be used to display a message in the system chat.

While operators are usually fairly intuitive to use, commands are often more complicated. As such, every single command (and every single operator) has a dedicated Community Wiki page documenting it. This makes the Community Wiki an essential resource for scripting as it can be consulted whenever an unfamiliar command is encountered or needs to be used. The documentation commonly includes information about the behaviour and effect of the command, its return value and the purpose and data types of its parameters.

ⓘ
Commands List can be found here: Scripting Commands.
Control Structures, Conditions and Booleans
Control Structures allow scripts to accomplish complex tasks. See the following:

if (damage player > 0.5) then
{
	player setDamage 0;
	systemChat "The player has been healed.";
}
else
{
	systemChat "The player is fine.";
};
This code behaves differently depending on the damage status of the player. The systemChat output and whether or not the player is healed changes dynamically based on how much health the player has when the code is executed.

Conditions
In the example above, the condition is damage player > 0.5. Like all conditions, it results in a Boolean value when evaluated:

First, damage player is evaluated and returns a number.
Then, the > operator compares that number to 0.5:
If the number is greater than 0.5, the > operator returns true.
If the number is less than or equal to 0.5, the > operator returns false.
Booleans
The data type Boolean only has two possible values: true and false.

Boolean Operations
There are three basic operations that can be performed on Boolean values:

Operation	Description	SQF Operator	SQF Command
NOT (Negation)	Inverts the input value.	!	not
AND (Conjunction)	Combines two Booleans into one. Only returns true if both input values are true.	&&	and
OR (Disjunction)	Combines two Booleans into one. Returns true if at least one of the input values is true.	||	or
Both the input and the output of these operations are Boolean values. Their behaviour is defined as follows:

NOT
Expression	Result
!true	false
!false	true
AND
Expression	Result
true && true	true
true && false	false
false && true	false
false && false	false
OR
Expression	Result
true || true	true
true || false	true
false || true	true
false || false	false
Complex Conditions
Boolean operations can be used to create complex conditions by combining multiple conditions into one.

if ((alive VIP_1 && triggerActivated VIP_1_Task_Complete) || (alive VIP_2 && triggerActivated VIP_2_Task_Complete)) then
{
	systemChat "At least one VIP has been rescued.";
};
ⓘ
Beginners sometimes write conditions such as if (Condition == true) or if (Condition == false).
While doing so is not a real error, it is unnecessary because Control Structures (and Triggers) always implicitly compare the condition to true.

The correct (as in faster, more common and more readable) way to write such conditions is if (Condition) and if (!Condition) respectively.
Arrays
An Array is a Data Type that can be seen as a list of items. This list can hold none to multiple elements of different types:

[]						// an empty array
[true]					// an array of 1 element (Boolean)
[0, 10, 20, 30, 40, 50]	// an array of 6 elements of Number type
["John Doe", 32, true]	// an array of 3 elements of different types (String, Number, Boolean)
An array is a useful way to keep data together and is used for example to store positions.

Positions
Positions are represented as 2D or 3D Arrays of Numbers (usually in the format [X, Y] or [X, Y, Z]) where X represents West-East, Y represents South-North and Z represents altitude. However, there are some important caveats and distinctions one should be aware of - for instance, the positions [0, 0, 0] ASL (Above Sea Level) and [0, 0, 0] AGL (Above Ground Level) are not necessarily equivalent. It is therefore highly recommended to read the Positions page before working with positions.

Script Files
Scripts are usually placed in Script Files. It is of course possible and sometimes even necessary to use short pieces of code in the Editor (e.g. in the On Activation expression of a Trigger), but scripts can become long and complex, and then working with them is far easier when they are properly placed in script files. Additionally, some features are only accessible through the use of script files (Event Scripts for example).

Script files are basically just text files with a certain filename extension. For script files, that file extension is .sqf (or .sqs), but in the broader context of Arma scripting, modification, configuration and mission design, more file extensions can be encountered: .ext, .hpp, .cpp and .cfg to mention the most common ones.

File Creation
Unfortunately, Windows does not make the creation of blank files with a desired file extension easily accessible.

For instance, a common pitfall when trying to use Description.ext (a file that is used to configure certain mission features such as the respawn settings) for the first time is (unknowingly) creating Description.ext.txt instead of Description.ext because the Windows File Explorer hides file extensions by default. Obviously, Description.ext.txt will not work and will not have any of the desired effects on the mission because the game does not recognize it as Description.ext, but identifying a wrong file extension as the root cause of an issue when troubleshooting is notoriously difficult as one is usually looking for errors in the code and not in the filename.

While there are many different ways to create a blank text file with a specific file extension, the easiest method using native Windows tools is probably this:

Preparation (only needs to be done once):
Open the File Explorer
Open the View tab at the top
Tick the File name extensions checkbox
File Creation:
Navigate to the location where you want to create a new script file
Right-click
Go to New
Click on Text Document
Rename New Text Document.txt to what you need
ⓘ
It is also possible to bypass Notepad's automatic addition of the .txt extension by wrapping the file name in quote, e.g "description.ext".
File Locations
In the context of mission creation, script files generally need to be placed in the corresponding scenario folder (often also called the mission root folder). Every mission has its own scenario folder, it is created by the Editor when saving the scenario for the first time. By default it only contains a single file called mission.sqm; this file mostly stores data regarding Editor-placed entities and does not need to be touched when scripting.

Description.ext and Event Scripts have to be placed directly in the root of the scenario folder (i.e. next to mission.sqm), but all other files can be placed in subfolders of the scenario folder. A well-structured scenario folder could look like this:

Apex%20Protocol.Tanoa/
├── functions/
│   ├── fn_myFirstFunction.sqf
│   └── fn_mySecondFunction.sqf
├── scripts/
│   ├── myFirstScript.sqf
│   └── mySecondScript.sqf
├── description.ext
├── initPlayerLocal.sqf
├── initServer.sqf
└── mission.sqm
Each scenario folder is stored in either the missions or the mpmissions subfolder of the folder containing the Arma Profile that was used to create the scenario. For instance, the path to the scenario folder from the example above could be:

C:\Users\Scott Miller\Documents\Arma 3 - Other Profiles\Keystone\missions\Apex%20Protocol.Tanoa
The Editor uses percent-encoding for scenario folder names, that is why whitespaces in the scenario name are replaced with %20.

ⓘ
The Eden Editor provides a useful shortcut to quickly open a mission's scenario folder in the Windows File Explorer: With the mission open in the Editor, go to Scenario in the top left and then click on Open Scenario Folder.
See Also:

2D Editor: External
Eden Editor: Scenario Folder
Profile (the possible profile folder paths are listed there)
Editing Script Files
Because script files are essentially plain text files, they can be edited with just about any text editor. For instance, the native Windows Notepad can be used, but working with it is not very comfortable. As such, regular scripters typically use more versatile applications such as Notepad++ or Visual Studio Code, usually in combination with plugins that add additional support for SQF. One feature commonly provided by these plugins is syntax highlighting, and for good reason: Syntax highlighting makes code significantly more readable and helps recognizing and avoiding basic syntax errors. Consequently, it is highly recommended to use syntax highlighting.

See Community Tools - Code Edition for a selection of community-made applications and plugins for Arma Scripting.

Script Execution
The execVM command is used to execute script files.

For instance, myFirstScript.sqf from the File Locations example above can simply be executed like so:

execVM "scripts\myFirstScript.sqf";
This can be done anywhere: Within another script, from the Debug Console, in the On Activation or On Deactivation expression of a Trigger or in the init field of an Object in the Editor.



Intermediate Scripting
🚧
TODO:
Functions
Namespaces, Scopes
Event Handlers
HashMaps


Advanced Scripting
🚧
TODO:
Multiplayer Scripting
GUIs
Code Optimisation
Debugging Techniques


Miscellaneous
ⓘ
This section contains content from an old version of this page which is due to be updated.


Before anything
Is your idea necessary?
Will players even notice or use what you want to script? Just because you can does not mean you should. Sometimes less is more!
Is it possible to do this in the editor?
The Eden Editor is a powerful tool and with it alone one can achieve a lot of things without writing a single line of code.
Poorly written scripts are a frequent cause of poor performance, both in singleplayer and multiplayer scenarios.
Can it be scripted using SQF?
This question might be hard to answer. Try to get as much information about what you want to do and what commands and functions there are before spending time on writing a script, just to find out that what you hoped to achieve is not possible after all.
ⓘ
Scripting is not the solution for everything!
Terms
The following is a collection of terms frequently encountered when talking or reading about scripting.

Game Engine
The core program of the game which executes your scripting commands at run time.
Script / Script File
Scripts are usually placed in script files. Script files contain code.
Syntax
See SQF Syntax (Arma, Arma 2, Arma 3).
See SQS Syntax (Operation Flashpoint, Arma).
Variables
A Variable is a named storage container for data.
The name of a variable is called its Identifier.
Data Types
The Data Type of a variable specifies which kind of data that variable can contain.
Operators
See Operators
Control Structures
See Control Structures
Functions
See Function
Must-Read Articles
Best Practices
See Code Best Practices

Debugging
Debugging Techniques
Community Tools - Debug Console/System
Optimisation
Code Optimisation
Mission Optimisation
Useful Links
These pages cover further aspects of scripting:

Example Code
Control Structures
Multiplayer Scripting
Exception handling
Script File
Function
SQS to SQF conversion
Consider the following resources for more general learning:

6thSense.eu Editing Guide
Fockers Arma 3 Scripting Guide (dead link)
Mr-Murray's Armed Assault Editing Guide - Deluxe Edition (dead link)
Excellent German SQF tutorial (YouTube)
Categories: To-doArma Scripting Tutorials



Getting Started
Page
Read
View source
View history
Categories: Arma 3Hints & Tips
Buying Arma 3
Starting with the game
Playing in Single Player
Playing in Multiplayer
Finding players


Buying Arma 3
Arma 3 is a Steam platform exclusive game and can be bought on the Arma 3 Steam page.

Editions
Arma 3 has some Editions and bundles to purchase. Bundles are always cheaper than purchasing products separately.

Arma 3 Gold Edition (Steam page) contains the base game, Apex, Contact, the Karts DLC, and art (soundtrack, digital artworks, maps, tactical guide).
Arma 3 Platinum Edition (Steam page) contains the base game, every expansions and every DLCs by Bohemia Interactive, and art.



The main two editions allowing you to enjoy Arma 3.
Edition Details
⚠
Note that no Creator DLCs (CDLCs) are included in these editions!
Content	Gold Edition	Platinum Edition
Arma 3	Checked	Checked
Soundtrack ("Bonus" directory)	Checked	Checked
BI 25th Anniversary (Steam soundtrack)	Checked	Checked
Digital Artworks	Checked	Checked
Maps	Checked	Checked
Tactical Guide	Checked	Checked
Karts	Checked	Checked
Helicopters		Checked
Marksmen		Checked
Apex	Checked	Checked
Laws of War		Checked
Jets		Checked
Tac-Ops		Checked
Tanks		Checked
Contact	Checked	Checked
Buying DLCs
You may wonder if you need to buy DLCs. You do not need anything to enjoy playing Arma 3 (but the base game), but depending on which experience you are after the common recommendations change:

For a Singleplayer experience, the base campaign, Arma 3 Laws of War and in an other style Arma 3 Contact singleplayer campaigns are considered among the best singleplayer moments. If you can afford it too, see also the Arma 3 Tac-Ops Mission Pack for a combat experience from multiple points of view.
For a Multiplayer experience, it is recommended to at least own Arma 3 Apex to be able to play with its assets and have access to the Tanoa terrain. The cooperation campaign is good to play through too.
Every asset such as weapons and vehicles provided by Bohemia Interactive are free to test in Arsenal (TUTORIALS > VIRTUAL ARSENAL). If you wonder if the DLC is worth your money, it is possible to try it for free.
ⓘ
For a list of Arma 3 available DLCs and extensions, see Arma 3, Arma 3 DLCs & Expansions.
For information about DLC assets restrictions, see Arma 3: DLC Restrictions.
⚠
Creator DLCs (CDLCs) are not always available to test for free and their assets are never included into the base game. You must purchase them or install the compatibility Mod for it (if exists) before using them.


Starting With the Game
You bought the game, downloaded it, installed it, configured it via the launcher, started it: now what?
If you are not familiar with the Arma series, a usual recommendation is to access the main menu and select Tutorial, you can find choices such as:

Read the Game Manual
Read the Default Keyboard Layout Cheatsheet (printable and foldable)
Head on the Game Options and change key bindings, languages and difficulty
See Arma 3: Performance Optimisation for more information on the settings
Read the in-game Field Manual (TUTORIAL > FIELD MANUAL)
Watch Community Guide videos (Steam page / YouTube)
Read and watch Dslyecxi's Tactical Guides (direct link to TTP3)

then…



Playing in Single Player

The Virtual Arsenal allows to try even non-owned DLC content.
In-Game Training
Play the VR Training missions to understand the principles
Play the Showcases to apply these principles in real action
Play the Bootcamp campaign
Practice weapons and vehicles in the Virtual Arsenal
Discover the available Terrains in Eden Editor
Fighting
Play the Single Player campaign "The East Wind" to learn to work in a team
Play the other Single Player content, according to your DLC list:
Arma 3 Tac-Ops Mission Pack
Arma 3 Laws of War's campaign
Arma 3 Contact's campaign


Playing in Multiplayer
ⓘ
Playing in Multiplayer is way different from Single Player; an AI can be predicted, its skill altered, its behaviour planned,
whereas an experienced human being will keep you on your toes and make you change tactics… under the threat of imminent death!
If you own Arma 3 Apex, play its Multiplayer campaign "Apex Protocol" with experienced friends
Hours of practice will help you:
Find the kind of game you like, among the various Multiplayer game types
Getting different experiences no training can bring (situational awareness, reflexes, specific cases)
If possible, try to play on multiple servers with friends or an Arma 3 Unit!
Joining a Modded Server
A non-official server may require mods to play. The game itself cannot download the mods and will only tell you what is missing.
Joining a server from the Launcher can download the required mods before launching the game; see more information at Arma 3: Launcher - Servers.



Steam Workshop 101
Arma 3 does support Steam Workshop. You can find mods (a.k.a addons) that add some assets, features and experiences that don't exist in vanilla (addon-free) Arma 3, or user-made scenarios providing another game experience.

To add and install Workshop items, follow these steps:

Download and Play a Scenario
Open the Arma 3 Steam Workshop and select the Scenario tag.
Find a scenario you like.
Click subscribe on Steam SubscribeButton.png to subscribe to a scenario. It will automatically download when the game is started.
Open the game and navigate to SINGLEPLAYER > SCENARIOS. If the mission has a Multiplayer/Co-Op tag on the workshop, you have to go to MULTIPLAYER > QUICK PLAY > HOST SERVER to see it.
The subscribed mission will be downloaded and found under the Steam Subscribed Content.
Download and Activate a Mod
Open the Arma 3 Steam Workshop and select the Mod tag.
Find a mod you like.
Click subscribe on Steam SubscribeButton.png to subscribe to a mod.
Start Arma 3 from your Steam Library, that will open Arma 3: Launcher.
Subscribed mods will be downloaded automatically.
Click the MODS tab.
Downloaded mods are automatically loaded. If you need to unload a mod, click the checkbox.
Press PLAY to launch Arma 3 with selected mods.
ⓘ
These tutorials and others (publishing to the workshop) can also be found on the Arma 3 website: Arma 3 Workshop 101.


Finding Players, Communities and Help
Official communication channels
Arma 3 Official Forums
Arma 3 Official Discord
#looking_for_game channel if you are looking for players
#looking_for_squad channel if you are looking for squads
#communities_arma channel if you are looking for communities
#singleplayer channel for… Single Player content advices and discussion
#scripting channel for help in scripting, as well as Arma 3 Scripting Commands
#community_wiki channel where discussions about articles on this wiki happen
And for all your other questions, #ask_questions_here is the channel to be!
Common Game Modes Servers
Exile Discord
Epoch Discord
Antistasi Discord
Arma RPG Life Discord
King Of The Hill / Wasteland Discord





Editing
Category
Discussion
Read
View source
View history
Help
Subcategories
This category has the following 15 subcategories, out of 15 total.

 AI‎ (14 P)
Arma: Tutorials‎ (5 C, 7 P)
 Arma 3: Controls‎ (3 P)
GUI Topics‎ (3 C, 15 P)
Mission Editing‎ (4 C, 15 P)
 Arma 3: MP Modes‎ (5 P)
Arma 3: Official Tools‎ (1 C, 38 P)
Particle System‎ (1 C, 5 P)
Reference Lists‎ (16 C, 3 P)
 Arma 3: Remote Execution‎ (11 P)
Arma 3: Scripting Commands‎ (4 C, 2,656 P)
Scripting Topics‎ (10 C, 24 P)
 Arma 3: Sound‎ (14 P)
 Arma 3: Vehicle Configuration‎ (19 P)
 Arma 3: Weapon & Magazine Configuration‎ (8 P)
Pages in category "Arma 3: Editing"
The following 111 pages are in this category, out of 111 total.

 
Addons
Arma 3: Advanced Helicopter Flight Model
Arma 3: Advanced Hints (Field Manual)
Arma 3: Aircraft Systems
Arma 3: Alien Entity Behavior
Arma 3: Animals: Ambient System
Arma 3: Animals: Override Default Animal Behaviour Via Script
Arma 3: Animations
Arma: Airport IDs
Arma: All-in-one Config
Arma 3: Arsenal
Arma 3: CBRN
CfgMissions
CfgPatches
Arma 3: Characters And Gear Encoding Guide
Arma 3: Characters Firegeometry Update
Class Inheritance
CMA:DevelopmentSetup
Arma 3: Common Terrain Creation Problems
Arma 3: Communication Menu
Arma 3: Countermeasures
Arma 3: Curator
Arma 3: Custom Info
Arma 3: Debug Console
Arma 3: Difficulty Settings
Arma 3: Dynamic Airport Configuration
Arma 3: Dynamic Groups
Arma 3: Dynamic Simulation
Arma 3: End Game Spectator Mode
Arma 3: Environment Metrics
Arma 3: Error Messages
Extensions
Arma 3: Firing Drills
Arma 3: Functions Library
Arma 3: Functions Viewer
Geometric Occluders
How to create destroyable wheels
Arma 3: Improved Fog
Arma 3: Infantry Metrics
Arma 3: Key Frame Animation
Arma 3: Leaflets
Arma 3: Lights
LITE mod version creation guide
Arma 3: Loading Screens
LOD
Arma 3: Main Menu
Arma 3: meta.cpp
Missions
Arma 3: Modded Keybinding
Arma 3: Modding Characters
Modules
Arma 3: Multi-Function Display (MFD) config reference
Arma 3: Named Properties
Arma 3: NameSound Setup
Arma 3: Notification
Objects.sav
OFPEC Tags List
Arma 3: Old Man Systems
Arma 3: ORBAT Viewer
Arma 3: Parallax Map
Arma 3: Porting Guidelines Overview
Arma 3: Probing Mechanics
Procedural Textures
Profile
Arma 3: Radio Protocol
Arma 3: Regular Expressions
Arma 3: Respawn
Arma 3: Revive
Arma 3: Ropes
RVMAT basics
Scripting Tags
Arma 3: Sensors Config Reference
Arma 3: Setting Textures for Wrecks
Arma 3: Shooting Targets
Simple Expression
Arma 3: Simple Objects
Arma 3: Soldier Protection
Arma 3: Spectrum Device
Arma 3: Splendid Animation Viewer
Arma 3: Splendid Camera
SQF Bytecode
Arma 3: Stamina
Arma 3: Steam Game Recording
Stringtable.xml
Arma 3: Task Framework
Arma 3: Terrain Creation
Texture Map Types
Texture Naming Conventions
Arma 3: Time Trials
Arma 3: Trees
Arma 3: Unit Insignia
UserActions
userconfig
Arma 3: Utilities
Arma 3: UVAnimations
Arma 3: Vegetation P3D
Vehicle Respawn
Arma 3: Virtual Reality Custom Courses
Visual Studio Code SQF Extensions
Arma 3: Visual Upgrade
A
Arma 3: CfgGlasses
Arma 3: CfgMagazines
Arma 3: CfgPatches CfgVehicles
Arma 3: CfgPatches CfgWeapons
Arma 3: CfgVehicles Backpacks
Arma 3: CfgWeapons Equipment
Arma 3: CfgWeapons Items
Arma 3: CfgWeapons Vehicle Weapons
Arma 3: CfgWeapons Weapons
Arma 3: Multiplayer Campaign Creation
Arma 3: Performance Profiling




Eden Editor
Category
Read
View source
View history
Help


edenEditor logo.png
Getting Started
Introduction
Switching from 2D Editor
Terminology

Interface
Menu Bar
Toolbar
Asset Browser
Status Bar
Controls

Asset Types
Objects
Groups
Custom Compositions
Triggers
Waypoints
Systems
Markers
Comments
Layers
Entity Editing
Placing
Transforming
Transforming Crew
Transformation Widget
Connecting
Attributes

Scenario
Scenario Attributes
Phases
Preview
Publishing
Scenario Folder

Modding Eden Editor
Modding Basics
Configuring Attributes
Eden Scripting Commands
Eden Event Handlers
Eden Actions
Object Categorization

See Also:	Commands	Functions	Event Handlers	Waypoints	Modules
3den promo 1.jpg
3den promo 2.jpg
3den promo 3.jpg
Subcategories
This category has the following 7 subcategories, out of 7 total.

A
 Eden Editor: Asset Types‎ (10 P)
E
 Arma 3: Editor Previews‎ (5,143 F)
 Eden Editor: Editing‎ (9 P)
G
 Eden Editor: Getting Started‎ (4 P)
I
 Eden Editor: Interface‎ (4 P)
M
Eden Editor: Modding‎ (2 C, 19 P)
S
 Eden Editor: Scenario‎ (4 P)



 