@{
    Version = 1
    Notes   = @'
Curated save/config locations for popular PC games.
Repacks (FitGirl, DODI, ElAmigos) do NOT move save files: a repack is just a
compressed installer of the original game files, so saves still land in the
game's normal per-user folders. Scene/emu save folders are listed separately
by the discovery engine (Public\Documents\Steam\CODEX, Goldberg, etc.).

Paths support these tokens:
  %USERPROFILE% %APPDATA% %LOCALAPPDATA% %LOCALLOW% %DOCUMENTS% %SAVEDGAMES%
  %PUBLIC% %PUBLICDOCS% %PROGRAMDATA% %GAMEDIR% %STEAMUSERDATA%
'@

    Games = @(

        # ---------------- Bethesda / Creation Engine ----------------
        @{
            Id = 'skyrimse'; Name = 'The Elder Scrolls V: Skyrim Special Edition'
            Aliases = @('Skyrim Special Edition','Skyrim SE','TESV Skyrim SE','Skyrim Anniversary Edition')
            Engine = 'Creation Engine'; SteamAppIds = @(489830)
            Paths = @('%DOCUMENTS%\My Games\Skyrim Special Edition')
            RegistryKeys = @(); Notes = 'Saves, plugins.txt and INI files.'
        }
        @{
            Id = 'skyrim'; Name = 'The Elder Scrolls V: Skyrim'
            Aliases = @('Skyrim','TESV Skyrim','Skyrim Legendary Edition')
            Engine = 'Creation Engine'; SteamAppIds = @(72850)
            Paths = @('%DOCUMENTS%\My Games\Skyrim')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'fallout4'; Name = 'Fallout 4'
            Aliases = @('Fallout 4 GOTY','Fallout IV')
            Engine = 'Creation Engine'; SteamAppIds = @(377160)
            Paths = @('%DOCUMENTS%\My Games\Fallout4')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'falloutnv'; Name = 'Fallout: New Vegas'
            Aliases = @('Fallout New Vegas','FalloutNV')
            Engine = 'Gamebryo'; SteamAppIds = @(22380)
            Paths = @('%DOCUMENTS%\My Games\FalloutNV')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'fallout3'; Name = 'Fallout 3'
            Aliases = @('Fallout 3 GOTY')
            Engine = 'Gamebryo'; SteamAppIds = @(22300)
            Paths = @('%DOCUMENTS%\My Games\Fallout3')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'starfield'; Name = 'Starfield'
            Aliases = @()
            Engine = 'Creation Engine 2'; SteamAppIds = @(1716740)
            Paths = @('%DOCUMENTS%\My Games\Starfield')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- CD Projekt Red ----------------
        @{
            Id = 'cyberpunk2077'; Name = 'Cyberpunk 2077'
            Aliases = @('Cyberpunk 2077 Phantom Liberty')
            Engine = 'REDengine 4'; SteamAppIds = @(1091500)
            Paths = @('%SAVEDGAMES%\CD Projekt Red\Cyberpunk 2077','%LOCALAPPDATA%\CD Projekt Red\Cyberpunk 2077')
            RegistryKeys = @(); Notes = 'Manual and quick saves plus user settings.'
        }
        @{
            Id = 'witcher3'; Name = 'The Witcher 3: Wild Hunt'
            Aliases = @('Witcher 3','The Witcher 3')
            Engine = 'REDengine 3'; SteamAppIds = @(292030)
            Paths = @('%DOCUMENTS%\The Witcher 3')
            RegistryKeys = @(); Notes = 'gamesaves, input settings and user config.'
        }

        # ---------------- Rockstar ----------------
        @{
            Id = 'gtav'; Name = 'Grand Theft Auto V'
            Aliases = @('GTA V','GTA 5','Grand Theft Auto 5')
            Engine = 'RAGE'; SteamAppIds = @(271590)
            Paths = @('%DOCUMENTS%\Rockstar Games\GTA V')
            RegistryKeys = @(); Notes = 'Profiles and settings. GTA Online data is server-side.'
        }
        @{
            Id = 'rdr2'; Name = 'Red Dead Redemption 2'
            Aliases = @('RDR2','Red Dead 2')
            Engine = 'RAGE'; SteamAppIds = @(1174180)
            Paths = @('%DOCUMENTS%\Rockstar Games\Red Dead Redemption 2','%STEAMUSERDATA%\1174180\remote')
            RegistryKeys = @(); Notes = 'Story-mode saves and profile.'
        }

        # ---------------- FromSoftware / Soulslike ----------------
        @{
            Id = 'eldenring'; Name = 'ELDEN RING'
            Aliases = @('Elden Ring','ELDENRING')
            Engine = 'FromSoftware'; SteamAppIds = @(1245620)
            Paths = @('%APPDATA%\EldenRing')
            RegistryKeys = @(); Notes = 'One .sl2 save file per Steam account.'
        }
        @{
            Id = 'dark souls3'; Name = 'DARK SOULS III'
            Aliases = @('Dark Souls 3','Dark Souls III')
            Engine = 'FromSoftware'; SteamAppIds = @(374320)
            Paths = @('%APPDATA%\DarkSoulsIII')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'darksoulsremastered'; Name = 'DARK SOULS: REMASTERED'
            Aliases = @('Dark Souls Remastered')
            Engine = 'FromSoftware'; SteamAppIds = @(570940)
            Paths = @('%DOCUMENTS%\NBGI\DarkSouls Remastered')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'sekiro'; Name = 'Sekiro: Shadows Die Twice'
            Aliases = @('Sekiro')
            Engine = 'FromSoftware'; SteamAppIds = @(814380)
            Paths = @('%APPDATA%\Sekiro')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'armoredcore6'; Name = 'ARMORED CORE VI FIRES OF RUBICON'
            Aliases = @('Armored Core 6','Armored Core VI')
            Engine = 'FromSoftware'; SteamAppIds = @(1888160)
            Paths = @('%APPDATA%\ArmoredCore6')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'liesofp'; Name = 'Lies of P'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1627720)
            Paths = @('%LOCALAPPDATA%\Lies of P\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'nioh2'; Name = 'Nioh 2'
            Aliases = @('Nioh 2 Complete Edition')
            Engine = 'Team Ninja'; SteamAppIds = @(1325200)
            Paths = @('%DOCUMENTS%\KoeiTecmo\NIOH2')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Larian / RPG ----------------
        @{
            Id = 'bg3'; Name = "Baldur's Gate 3"
            Aliases = @('Baldurs Gate 3','BG3')
            Engine = 'Divinity 4.0'; SteamAppIds = @(1086940)
            Paths = @('%LOCALAPPDATA%\Larian Studios\Baldur''s Gate 3')
            RegistryKeys = @(); Notes = 'PlayerProfiles contains saves, settings and mods list.'
        }
        @{
            Id = 'divinityos2'; Name = 'Divinity: Original Sin 2'
            Aliases = @('Divinity Original Sin 2','DOS2')
            Engine = 'Divinity 4.0'; SteamAppIds = @(435150)
            Paths = @('%DOCUMENTS%\Larian Studios\Divinity Original Sin 2')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'discoelysium'; Name = 'Disco Elysium'
            Aliases = @('Disco Elysium The Final Cut')
            Engine = 'Unity'; SteamAppIds = @(632470)
            Paths = @('%LOCALLOW%\ZAUM Studio\Disco Elysium')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Capcom ----------------
        @{
            Id = 'mhw'; Name = 'Monster Hunter: World'
            Aliases = @('Monster Hunter World','MHW','Monster Hunter World Iceborne')
            Engine = 'MT Framework'; SteamAppIds = @(582010)
            Paths = @('%STEAMUSERDATA%\582010\remote')
            RegistryKeys = @(); Notes = 'Steam cloud-style userdata folder.'
        }
        @{
            Id = 'mhrise'; Name = 'Monster Hunter Rise'
            Aliases = @('MHRise','Monster Hunter Rise Sunbreak')
            Engine = 'RE Engine'; SteamAppIds = @(1446780)
            Paths = @('%STEAMUSERDATA%\1446780\remote')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 're4remake'; Name = 'Resident Evil 4'
            Aliases = @('Resident Evil 4 Remake','RE4 Remake','RE4')
            Engine = 'RE Engine'; SteamAppIds = @(2050650)
            Paths = @('%STEAMUSERDATA%\2050650\remote')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'revillage'; Name = 'Resident Evil Village'
            Aliases = @('Resident Evil 8','RE Village','RE8')
            Engine = 'RE Engine'; SteamAppIds = @(1196590)
            Paths = @('%STEAMUSERDATA%\1196590\remote')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'dmc5'; Name = 'Devil May Cry 5'
            Aliases = @('DMC5','Devil May Cry V')
            Engine = 'RE Engine'; SteamAppIds = @(601150)
            Paths = @('%STEAMUSERDATA%\601150\remote')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Sony / PlayStation ports ----------------
        @{
            Id = 'godofwar'; Name = 'God of War'
            Aliases = @('God of War 2018')
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1593500)
            Paths = @('%SAVEDGAMES%\God of War')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'godofwarragnarok'; Name = 'God of War Ragnarok'
            Aliases = @('God of War Ragnarök')
            Engine = 'Unreal Engine 4'; SteamAppIds = @(2322010)
            Paths = @('%SAVEDGAMES%\God of War Ragnarok')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'horizonzerodawn'; Name = 'Horizon Zero Dawn'
            Aliases = @('Horizon Zero Dawn Complete Edition','HZD')
            Engine = 'Decima'; SteamAppIds = @(1151640)
            Paths = @('%DOCUMENTS%\Horizon Zero Dawn')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'horizonforbiddenwest'; Name = 'Horizon Forbidden West'
            Aliases = @('HFW','Horizon Forbidden West Complete Edition')
            Engine = 'Decima'; SteamAppIds = @(2420110)
            Paths = @('%DOCUMENTS%\Horizon Forbidden West')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'ghostoftsushima'; Name = 'Ghost of Tsushima'
            Aliases = @("Ghost of Tsushima DIRECTOR'S CUT",'Ghost of Tsushima Directors Cut')
            Engine = 'Sucker Punch'; SteamAppIds = @(2215430)
            Paths = @("%DOCUMENTS%\Ghost of Tsushima DIRECTOR'S CUT")
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'spidermanremastered'; Name = "Marvel's Spider-Man Remastered"
            Aliases = @('Spider-Man Remastered','Spiderman Remastered')
            Engine = 'Insomniac'; SteamAppIds = @(1817070)
            Paths = @("%DOCUMENTS%\Marvel's Spider-Man Remastered")
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'spidermanmiles'; Name = "Marvel's Spider-Man: Miles Morales"
            Aliases = @('Spider-Man Miles Morales','Spiderman Miles Morales')
            Engine = 'Insomniac'; SteamAppIds = @(1817190)
            Paths = @("%DOCUMENTS%\Marvel's Spider-Man Miles Morales")
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'daysgone'; Name = 'Days Gone'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1259420)
            Paths = @('%LOCALAPPDATA%\BendGame\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'detroit'; Name = 'Detroit: Become Human'
            Aliases = @('Detroit Become Human')
            Engine = 'Quantic Dream'; SteamAppIds = @(1222140)
            Paths = @('%LOCALAPPDATA%\Quantic Dream\Detroit Become Human')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Ubisoft ----------------
        @{
            Id = 'acvalhalla'; Name = "Assassin's Creed Valhalla"
            Aliases = @('AC Valhalla','Assassins Creed Valhalla')
            Engine = 'AnvilNext 2.0'; SteamAppIds = @()
            Paths = @("%DOCUMENTS%\Assassin's Creed Valhalla",'%LOCALAPPDATA%\Ubisoft Game Launcher\savegames')
            RegistryKeys = @(); Notes = 'Ubisoft Connect savegames folder is account-ID based; see README.'
        }
        @{
            Id = 'acodyssey'; Name = "Assassin's Creed Odyssey"
            Aliases = @('AC Odyssey','Assassins Creed Odyssey')
            Engine = 'AnvilNext 2.0'; SteamAppIds = @(812140)
            Paths = @("%DOCUMENTS%\Assassin's Creed Odyssey",'%LOCALAPPDATA%\Ubisoft Game Launcher\savegames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'acorigins'; Name = "Assassin's Creed Origins"
            Aliases = @('AC Origins','Assassins Creed Origins')
            Engine = 'AnvilNext 2.0'; SteamAppIds = @(582160)
            Paths = @("%DOCUMENTS%\Assassin's Creed Origins",'%LOCALAPPDATA%\Ubisoft Game Launcher\savegames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'farcry6'; Name = 'Far Cry 6'
            Aliases = @('FarCry 6')
            Engine = 'Dunia'; SteamAppIds = @()
            Paths = @('%DOCUMENTS%\My Games\Far Cry 6')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'farcry5'; Name = 'Far Cry 5'
            Aliases = @('FarCry 5')
            Engine = 'Dunia'; SteamAppIds = @(552520)
            Paths = @('%DOCUMENTS%\My Games\Far Cry 5')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'watchdogs2'; Name = 'Watch Dogs 2'
            Aliases = @('Watch_Dogs 2')
            Engine = 'Disrupt'; SteamAppIds = @(447040)
            Paths = @('%DOCUMENTS%\My Games\Watch_Dogs2')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- WB / Arkham ----------------
        @{
            Id = 'arkhamknight'; Name = 'Batman: Arkham Knight'
            Aliases = @('Batman Arkham Knight')
            Engine = 'Unreal Engine 3'; SteamAppIds = @(208650)
            Paths = @('%DOCUMENTS%\WB Games\Batman Arkham Knight')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'shadowofwar'; Name = 'Middle-earth: Shadow of War'
            Aliases = @('Shadow of War')
            Engine = 'LithTech'; SteamAppIds = @(356190)
            Paths = @('%DOCUMENTS%\WB Games\Shadow of War')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'madmax'; Name = 'Mad Max'
            Aliases = @()
            Engine = 'Avalanche'; SteamAppIds = @(234140)
            Paths = @('%DOCUMENTS%\WB Games\Mad Max')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Other AAA ----------------
        @{
            Id = 'hogwartslegacy'; Name = 'Hogwarts Legacy'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(990080)
            Paths = @('%LOCALAPPDATA%\Hogwarts Legacy\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'blackmythwukong'; Name = 'Black Myth: Wukong'
            Aliases = @('Black Myth Wukong')
            Engine = 'Unreal Engine 5'; SteamAppIds = @(2358720)
            Paths = @('%LOCALAPPDATA%\b1\Saved\SaveGames','%LOCALAPPDATA%\BlackMythWukong\b1\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'atomicheart'; Name = 'Atomic Heart'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(668580)
            Paths = @('%LOCALAPPDATA%\AtomicHeart\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'dyinglight2'; Name = 'Dying Light 2'
            Aliases = @('Dying Light 2 Stay Human')
            Engine = 'C-Engine'; SteamAppIds = @(534380)
            Paths = @('%LOCALAPPDATA%\Dying Light 2\out\save')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'deadisland2'; Name = 'Dead Island 2'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(934700)
            Paths = @('%LOCALAPPDATA%\DeadIsland2\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'metroexodus'; Name = 'Metro Exodus'
            Aliases = @('Metro Exodus Enhanced Edition')
            Engine = '4A Engine'; SteamAppIds = @(412020)
            Paths = @('%LOCALAPPDATA%\Metro Exodus\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'sniperelite5'; Name = 'Sniper Elite 5'
            Aliases = @()
            Engine = 'Asura'; SteamAppIds = @(1029690)
            Paths = @('%LOCALAPPDATA%\SniperElite5\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'ittakestwo'; Name = 'It Takes Two'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1426210)
            Paths = @('%LOCALAPPDATA%\ItTakesTwo')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'awayout'; Name = 'A Way Out'
            Aliases = @()
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1222700)
            Paths = @('%LOCALAPPDATA%\AWayOut')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = '007firstlight'; Name = '007 First Light'
            Aliases = @('James Bond 007 First Light','First Light')
            Engine = 'Glacier 2'; SteamAppIds = @(3768760)
            Paths = @(
                '%APPDATA%\IO Interactive\Epic',
                '%APPDATA%\IO Interactive\007 First Light',
                '%LOCALAPPDATA%\IO Interactive\007 First Light',
                '%STEAMUSERDATA%\3768760',
                '%APPDATA%\GSE Saves\3768760',
                '%APPDATA%\Goldberg SteamEmu Saves\3768760',
                '%DOCUMENTS%\CPY_SAVES\3768760',
                '%PUBLICDOCS%\Steam\CODEX\3768760',
                '%PUBLICDOCS%\Steam\RUNE\3768760'
            )
            RegistryKeys = @('HKCU\Software\IO Interactive\007 First Light'); Notes = 'Steam saves via userdata\3768760; Epic path has a per-account id subfolder.'
        }
        @{
            Id = 'hitman3'; Name = 'HITMAN 3'
            Aliases = @('Hitman 3','HITMAN 3')
            Engine = 'Glacier 2'; SteamAppIds = @(1659040)
            Paths = @(
                '%APPDATA%\IO Interactive\HITMAN3',
                '%LOCALAPPDATA%\IO Interactive\HITMAN3',
                '%STEAMUSERDATA%\1659040',
                '%APPDATA%\GSE Saves\1659040',
                '%APPDATA%\Goldberg SteamEmu Saves\1659040',
                '%PUBLICDOCS%\Steam\RUNE\1659040',
                '%PUBLICDOCS%\Steam\CODEX\1659040'
            )
            RegistryKeys = @('HKCU\Software\IO Interactive\HITMAN3'); Notes = ''
        }

        # ---------------- Strategy / simulation ----------------
        @{
            Id = 'civ6'; Name = "Sid Meier's Civilization VI"
            Aliases = @('Civilization 6','Civ 6','Civilization VI')
            Engine = 'Civilization'; SteamAppIds = @(289070)
            Paths = @('%LOCALAPPDATA%\Firaxis Games\Sid Meier''s Civilization VI')
            RegistryKeys = @(); Notes = 'Saves, logs and user options.'
        }
        @{
            Id = 'citiesskylines'; Name = 'Cities: Skylines'
            Aliases = @('Cities Skylines')
            Engine = 'Unity'; SteamAppIds = @(255710)
            Paths = @('%LOCALAPPDATA%\Colossal Order\Cities_Skylines')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'citiesskylines2'; Name = 'Cities: Skylines II'
            Aliases = @('Cities Skylines 2','Cities Skylines II')
            Engine = 'Unity'; SteamAppIds = @(949230)
            Paths = @('%LOCALLOW%\Colossal Order\Cities Skylines II')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'totalwarwarhammer3'; Name = 'Total War: Warhammer III'
            Aliases = @('Total War Warhammer 3','TWW3')
            Engine = 'Total War'; SteamAppIds = @(1142710)
            Paths = @('%APPDATA%\The Creative Assembly\Warhammer3')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'aoe2de'; Name = 'Age of Empires II: Definitive Edition'
            Aliases = @('Age of Empires 2 DE','AoE2 DE')
            Engine = 'Genie'; SteamAppIds = @(813780)
            Paths = @('%USERPROFILE%\Games\Age of Empires 2 DE')
            RegistryKeys = @(); Notes = 'Contains profile and savegame per Steam ID.'
        }
        @{
            Id = 'coh2'; Name = 'Company of Heroes 2'
            Aliases = @('CoH2')
            Engine = 'Essence'; SteamAppIds = @(231430)
            Paths = @('%DOCUMENTS%\My Games\Company of Heroes 2')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'bannerlord'; Name = 'Mount & Blade II: Bannerlord'
            Aliases = @('Bannerlord','Mount and Blade 2 Bannerlord')
            Engine = 'Bannerlord'; SteamAppIds = @(261550)
            Paths = @('%DOCUMENTS%\Mount and Blade II Bannerlord\Game Saves')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'warband'; Name = 'Mount & Blade: Warband'
            Aliases = @('Mount and Blade Warband')
            Engine = 'Warband'; SteamAppIds = @(48700)
            Paths = @('%DOCUMENTS%\Mount&Blade Warband Savegames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'eurotrucksim2'; Name = 'Euro Truck Simulator 2'
            Aliases = @('ETS2')
            Engine = 'Prism3D'; SteamAppIds = @(227300)
            Paths = @('%DOCUMENTS%\Euro Truck Simulator 2\profiles','%DOCUMENTS%\Euro Truck Simulator 2\save')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'americantrucksim'; Name = 'American Truck Simulator'
            Aliases = @('ATS')
            Engine = 'Prism3D'; SteamAppIds = @(270880)
            Paths = @('%DOCUMENTS%\American Truck Simulator\profiles','%DOCUMENTS%\American Truck Simulator\save')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'farmsim22'; Name = 'Farming Simulator 22'
            Aliases = @('Farming Simulator 2022','FS22')
            Engine = 'GIANTS'; SteamAppIds = @(1248130)
            Paths = @('%DOCUMENTS%\My Games\FarmingSimulator2022')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'sims4'; Name = 'The Sims 4'
            Aliases = @('Sims 4')
            Engine = 'Sims'; SteamAppIds = @()
            Paths = @('%DOCUMENTS%\Electronic Arts\The Sims 4')
            RegistryKeys = @(); Notes = 'saves, Tray, Mods and settings.'
        }
        @{
            Id = 'footballmanager24'; Name = 'Football Manager 2024'
            Aliases = @('FM24','Football Manager 2024')
            Engine = 'FM'; SteamAppIds = @(2252570)
            Paths = @('%DOCUMENTS%\Sports Interactive\Football Manager 2024')
            RegistryKeys = @(); Notes = 'games, tactics and editor data.'
        }
        @{
            Id = 'fifa23'; Name = 'FIFA 23'
            Aliases = @('FIFA 23')
            Engine = 'Frostbite'; SteamAppIds = @(1811260)
            Paths = @('%DOCUMENTS%\FIFA 23')
            RegistryKeys = @(); Notes = 'Career saves and settings.'
        }
        @{
            Id = 'fc24'; Name = 'EA SPORTS FC 24'
            Aliases = @('FC 24','EA FC 24','EA Sports FC 24')
            Engine = 'Frostbite'; SteamAppIds = @(2195250)
            Paths = @('%DOCUMENTS%\FC 24')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Survival / sandbox / indie ----------------
        @{
            Id = 'stardewvalley'; Name = 'Stardew Valley'
            Aliases = @('Stardew')
            Engine = 'XNA/MonoGame'; SteamAppIds = @(413150)
            Paths = @('%APPDATA%\StardewValley\Saves')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'terraria'; Name = 'Terraria'
            Aliases = @()
            Engine = 'Terraria'; SteamAppIds = @(105600)
            Paths = @('%DOCUMENTS%\My Games\Terraria')
            RegistryKeys = @(); Notes = 'Players, Worlds and config.'
        }
        @{
            Id = 'minecraftjava'; Name = 'Minecraft: Java Edition'
            Aliases = @('Minecraft Java','Minecraft')
            Engine = 'Java'; SteamAppIds = @()
            Paths = @('%APPDATA%\.minecraft\saves')
            RegistryKeys = @(); Notes = 'World saves.'
        }
        @{
            Id = 'valheim'; Name = 'Valheim'
            Aliases = @()
            Engine = 'Unity'; SteamAppIds = @(892970)
            Paths = @('%LOCALLOW%\IronGate\Valheim')
            RegistryKeys = @(); Notes = 'worlds, characters and config.'
        }
        @{
            Id = 'palworld'; Name = 'Palworld'
            Aliases = @('Palworld Xbox')
            Engine = 'Unreal Engine 5'; SteamAppIds = @(1623730)
            Paths = @('%LOCALAPPDATA%\Pal\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'satisfactory'; Name = 'Satisfactory'
            Aliases = @()
            Engine = 'Unreal Engine 5'; SteamAppIds = @(526870)
            Paths = @('%LOCALAPPDATA%\FactoryGame\Saved\SaveGames')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'factorio'; Name = 'Factorio'
            Aliases = @()
            Engine = 'Factorio'; SteamAppIds = @(427520)
            Paths = @('%APPDATA%\Factorio\saves')
            RegistryKeys = @(); Notes = 'Also keeps config and mods next to saves.'
        }
        @{
            Id = 'rimworld'; Name = 'RimWorld'
            Aliases = @()
            Engine = 'Unity'; SteamAppIds = @(294100)
            Paths = @('%LOCALLOW%\Ludeon Studios\RimWorld by Ludeon Studios\Saves')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'subnautica'; Name = 'Subnautica'
            Aliases = @()
            Engine = 'Unity'; SteamAppIds = @(264710)
            Paths = @('%LOCALLOW%\Unknown Worlds\Subnautica')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'nomanssky'; Name = "No Man's Sky"
            Aliases = @('No Mans Sky','NMS')
            Engine = 'NMS'; SteamAppIds = @(275850)
            Paths = @('%APPDATA%\HelloGames\NMS')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'ark'; Name = 'ARK: Survival Evolved'
            Aliases = @('ARK Survival Evolved','ARK')
            Engine = 'Unreal Engine 4'; SteamAppIds = @(346110)
            Paths = @('%LOCALAPPDATA%\ARK\Saved')
            RegistryKeys = @(); Notes = 'Single-player and non-dedicated saves.'
        }
        @{
            Id = 'hollowknight'; Name = 'Hollow Knight'
            Aliases = @()
            Engine = 'Unity'; SteamAppIds = @(367520)
            Paths = @('%LOCALLOW%\Team Cherry\Hollow Knight')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'hades'; Name = 'Hades'
            Aliases = @()
            Engine = 'Supergiant'; SteamAppIds = @(1145360)
            Paths = @('%SAVEDGAMES%\Hades')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'celeste'; Name = 'Celeste'
            Aliases = @()
            Engine = 'XNA'; SteamAppIds = @(504230)
            Paths = @('%LOCALAPPDATA%\Celeste')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'undertale'; Name = 'Undertale'
            Aliases = @()
            Engine = 'GameMaker'; SteamAppIds = @(391540)
            Paths = @('%LOCALAPPDATA%\UNDERTALE')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'deltarune'; Name = 'Deltarune'
            Aliases = @()
            Engine = 'GameMaker'; SteamAppIds = @(1671210)
            Paths = @('%LOCALAPPDATA%\DELTARUNE')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'cuphead'; Name = 'Cuphead'
            Aliases = @()
            Engine = 'Unity'; SteamAppIds = @(268910)
            Paths = @('%APPDATA%\Cuphead')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'oriwotw'; Name = 'Ori and the Will of the Wisps'
            Aliases = @('Ori WotW')
            Engine = 'Unity'; SteamAppIds = @(1057090)
            Paths = @('%LOCALAPPDATA%\Ori and the Will of the Wisps')
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Anime / fighting (UE4 + scene emu saves) ----------------
        @{
            Id = 'jumpforce'; Name = 'JUMP FORCE'
            Aliases = @('Jump Force','JumpForce','JUMP FORCE Deluxe Edition')
            Engine = 'Unreal Engine 4'; SteamAppIds = @(816020)
            Paths = @(
                '%LOCALAPPDATA%\JUMP FORCE\Saved\SaveGames',
                '%STEAMUSERDATA%\816020\remote',
                '%DOCUMENTS%\CPY_SAVES\816020',
                '%APPDATA%\GSE Saves\816020',
                '%LOCALAPPDATA%\GSE Saves\816020',
                '%PROGRAMDATA%\GSE Saves\816020',
                '%APPDATA%\Goldberg SteamEmu Saves\816020',
                '%PUBLICDOCS%\Steam\CODEX\816020',
                '%PUBLICDOCS%\Steam\RUNE\816020',
                '%PUBLICDOCS%\Steam\PLAZA\816020'
            )
            RegistryKeys = @(); Notes = 'Story progress, characters and costumes. CPY/GSE/Goldberg variants included.'
        }
        @{
            Id = 'myherojustice2'; Name = "My Hero One's Justice 2"
            Aliases = @('My Hero Academia One''s Justice 2','MHOJ2','My Hero Ones Justice 2')
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1227500)
            Paths = @(
                '%LOCALAPPDATA%\My Hero One''s Justice 2\Saved\SaveGames',
                '%STEAMUSERDATA%\1227500\remote',
                '%DOCUMENTS%\CPY_SAVES\1227500',
                '%APPDATA%\GSE Saves\1227500',
                '%APPDATA%\Goldberg SteamEmu Saves\1227500',
                '%PUBLICDOCS%\Steam\CODEX\1227500'
            )
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'onepieceodyssey'; Name = 'ONE PIECE ODYSSEY'
            Aliases = @('One Piece Odyssey','ONE PIECE ODYSSEY Deluxe Edition')
            Engine = 'Unreal Engine 4'; SteamAppIds = @(1984490)
            Paths = @(
                '%LOCALAPPDATA%\ONE PIECE ODYSSEY\Saved\SaveGames',
                '%STEAMUSERDATA%\1984490\remote',
                '%DOCUMENTS%\CPY_SAVES\1984490',
                '%APPDATA%\GSE Saves\1984490',
                '%APPDATA%\Goldberg SteamEmu Saves\1984490'
            )
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'tekken8'; Name = 'TEKKEN 8'
            Aliases = @('Tekken 8','TEKKEN8')
            Engine = 'Unreal Engine 5'; SteamAppIds = @(1778820)
            Paths = @(
                '%LOCALAPPDATA%\TEKKEN 8\Saved\SaveGames',
                '%STEAMUSERDATA%\1778820\remote',
                '%DOCUMENTS%\CPY_SAVES\1778820',
                '%APPDATA%\GSE Saves\1778820',
                '%APPDATA%\Goldberg SteamEmu Saves\1778820'
            )
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'anothercrab'; Name = "Another Crab's Treasure"
            Aliases = @('Another Crabs Treasure','AnotherCrab')
            Engine = 'Unity'; SteamAppIds = @(1887840)
            Paths = @(
                '%LOCALLOW%\Aggro Crab\Another Crab''s Treasure',
                '%STEAMUSERDATA%\1887840\remote',
                '%APPDATA%\GSE Saves\1887840',
                '%APPDATA%\Goldberg SteamEmu Saves\1887840'
            )
            RegistryKeys = @(); Notes = ''
        }

        # ---------------- Misc / older ----------------
        @{
            Id = 'kingdomcome'; Name = 'Kingdom Come: Deliverance'
            Aliases = @('KCD','Kingdom Come Deliverance')
            Engine = 'CryEngine'; SteamAppIds = @(379430)
            Paths = @('%SAVEDGAMES%\kingdomcome\saves')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'kingdomcome2'; Name = 'Kingdom Come: Deliverance II'
            Aliases = @('KCD2','Kingdom Come Deliverance 2')
            Engine = 'CryEngine'; SteamAppIds = @(1771300)
            Paths = @('%SAVEDGAMES%\kingdomcome2\saves')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'skyrimvr'; Name = 'The Elder Scrolls V: Skyrim VR'
            Aliases = @('Skyrim VR')
            Engine = 'Creation Engine'; SteamAppIds = @(611670)
            Paths = @('%DOCUMENTS%\My Games\Skyrim VR')
            RegistryKeys = @(); Notes = ''
        }
        @{
            Id = 'nioh1'; Name = 'Nioh: Complete Edition'
            Aliases = @('Nioh')
            Engine = 'Team Ninja'; SteamAppIds = @(485510)
            Paths = @('%DOCUMENTS%\KoeiTecmo\NIOH')
            RegistryKeys = @(); Notes = ''
        }
    )
}
