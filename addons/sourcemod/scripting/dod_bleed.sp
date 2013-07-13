/**
* DoD:S Bleedings by Root
*
* Description:
*   Makes player bleeding after taking X damage for Y health every Z seconds.
*
* Version 1.2
* Changelog & more info at http://goo.gl/4nKhJ
*/

#pragma semicolon 1

#include <sdkhooks>

#define PLUGIN_NAME    "DoD:S Bleed"
#define PLUGIN_VERSION "1.2"

// Maximum players that DoD:S support
#define DOD_MAXPLAYERS 33

enum BleedInfoEnum
{
	enabled,
	attacker,
	health,
	curhealth,
	damage,

	BleedInfo_Size
};

// Hitgroups in DoD:S
enum HitGroups
{
	generic, // unused
	head,
	body,
	chest, // unused
	left_arm,
	right_arm,
	left_leg,
	right_leg
};

// ====[ VARIABLES ]=========================================================
enum BleedHitGroups
{
	Handle:HEAD,
	Handle:BODY,
	Handle:OTHER
}

new	Bleed_Damage[BleedHitGroups],
	Handle:Bleed_Mode = INVALID_HANDLE,
	Handle:Bleed_Health = INVALID_HANDLE,
	Handle:Bleed_Delay = INVALID_HANDLE,
	Handle:GlobalBleedingTimer = INVALID_HANDLE,
	bool:BleedInfo[DOD_MAXPLAYERS + 1][BleedInfo_Size];

// ====[ PLUGIN ]============================================================
public Plugin:myinfo =
{
	name        = PLUGIN_NAME,
	author      = "Root",
	description = "Enables player bleeding after taking X damage for Y health every Z seconds",
	version     = PLUGIN_VERSION,
	url         = "http://dodsplugins.com/"
};


/* OnPluginStart()
 *
 * When the plugin starts up.
 * -------------------------------------------------------------------------- */
public OnPluginStart()
{
	// FCVAR_DONTRECORD dont saves version convar in plugin's config
	CreateConVar("dod_bleeding_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_NOTIFY|FCVAR_DONTRECORD);

	// Create plugin's console variables
	Bleed_Damage[HEAD]  = CreateConVar("dod_bleed_damage_head",  "4", "Determines damage to take to a player which got hit in the head", FCVAR_PLUGIN, true, 1.0, true, 100.0);
	Bleed_Damage[BODY]  = CreateConVar("dod_bleed_damage_chest", "3", "Determines damage to take to a player which got hit in a body",   FCVAR_PLUGIN, true, 1.0, true, 100.0);
	Bleed_Damage[OTHER] = CreateConVar("dod_bleed_damage_other", "2", "Determines default damage to take to a player while bleeding",    FCVAR_PLUGIN, true, 1.0, true, 100.0);

	Bleed_Mode   = CreateConVar("dod_bleed_mode",   "0",   "Determines a mode to start bleeding\n0 = If player is having less than X health\n1 = If player got damaged for more than X health", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	Bleed_Health = CreateConVar("dod_bleed_health", "30",  "If mode is set to 0, start bleeding if player got less health that this value, otherwise start bleeding when player got damaged for more than this value", FCVAR_PLUGIN, true, 0.0, true, 100.0);
	Bleed_Delay  = CreateConVar("dod_bleed_delay",  "1.5", "Delay between taking damage while bleeding (in seconds)", FCVAR_PLUGIN, true, 0.1);

	// Hook changes only for delay convar to properly set timer
	HookConVarChange(Bleed_Delay, OnDelayChange);

	// Hook spawn event and damage event to properly set bleedings (disable and enable respectively)
	HookEvent("player_spawn", Event_Player_Spawn);
	HookEvent("dod_stats_player_damage", Event_Player_Damaged);

	// Load plugin config at every mapchange
	AutoExecConfig(true, "dod_bleed");
}

/* OnConVarChange()
 *
 * Called when timer's value is changed.
 * -------------------------------------------------------------------------- */
public OnDelayChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	// Check whether or not timer is enabled
	if (GlobalBleedingTimer)
	{
		// Close previous timer
		CloseHandle(GlobalBleedingTimer);

		// And recreate it but with newer value
		GlobalBleedingTimer = CreateTimer(StringToFloat(newValue), Timer_Bleeding, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	}
}

/* OnMapStart()
 *
 * When the map starts.
 * -------------------------------------------------------------------------- */
public OnMapStart()
{
	// Create new timer at every mapchange, because TIMER_FLAG_NO_MAPCHANGE is used
	GlobalBleedingTimer = CreateTimer(GetConVarFloat(Bleed_Delay), Timer_Bleeding, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
}

/* Event_Player_Spawn()
 *
 * Called when a player spawns.
 * -------------------------------------------------------------------------- */
public Event_Player_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	// At every respawn reset damage and make sure player is not bleeding anymore
	StopBleed(GetClientOfUserId(GetEventInt(event, "userid")));
}

/* Event_Player_Damage()
 *
 * Called when a player damages another.
 * -------------------------------------------------------------------------- */
public Event_Player_Damaged(Handle:event, const String:name[], bool:dontBroadcast)
{
	new attackerid = GetEventInt(event, "attacker");
	new victimid   = GetClientOfUserId(GetEventInt(event, "victim"));
	new hitgroupid = GetEventInt(event, "hitgroup");

	// Get victim's health and value to start bleeding, because values will be used more than once
	new victimhealth   = GetClientHealth(victimid);
	new bleedinghealth = GetConVarInt(Bleed_Health);

	// Retrieve mode
	switch (GetConVarBool(Bleed_Mode))
	{
		// Bleed if player got less health than value of ConVar
		case false:
		{
			if (victimhealth <= bleedinghealth)
			{
				StartBleed(victimid, attackerid, hitgroupid, victimhealth);
			}
		}
		case true:
		{
			// Start bleeding if player taken X damage (doesn't matter how many health had and having right now)
			if (GetEventInt(event, "damage") >= bleedinghealth)
			{
				StartBleed(victimid, attackerid, hitgroupid, victimhealth);
			}
		}
	}
}

/* Timer_Bleeding()
 *
 * Takes a X damage to a player every Y seconds.
 * -------------------------------------------------------------------------- */
public Action:Timer_Bleeding(Handle:timer)
{
	// Loop through all clients
	for (new i = 1; i <= MaxClients; i++)
	{
		// Ignore not yet connected and dead players
		if (IsClientInGame(i) && IsPlayerAlive(i))
		{
			// There are any bleeding players?
			if (bool:BleedInfo[i][enabled] == true)
			{
				// Retrieve the damage from every hitgroup
				new dmg = BleedInfo[i][damage];
				switch (GetConVarBool(Bleed_Mode))
				{
					case false:
					{
						new bleedinghealth = GetConVarInt(Bleed_Health);

						// If player is having less health than initalized in appropriate cvar...
						if (BleedInfo[i][health] <= bleedinghealth)
						{
							// ...take X damage (depends on unique value) every Y seconds
							SDKHooks_TakeDamage(i, 0, GetClientOfUserId(BleedInfo[i][attacker]), float(dmg));
						}
						if (GetClientHealth(i) > bleedinghealth)
						{
							// However if player is having more health - disable bleeding
							StopBleed(i);
						}
					}
					case true:
					{
						// Get and set current health every time player is bleeding
						new oldhp  = BleedInfo[i][curhealth];

						// Take damage using same way
						SDKHooks_TakeDamage(i, 0, GetClientOfUserId(BleedInfo[i][attacker]), float(dmg));

						// Just subtract amount of current health depends on damage
						oldhp -= dmg;

						if (GetClientHealth(i) > oldhp)
						{
							// Stop bleeding if player had any health boost
							StopBleed(i);
						}
					}
				}
			}
		}
	}
}

/* StartBleed()
 *
 * Makes player bleeding.
 * -------------------------------------------------------------------------- */
StartBleed(client, attackerid, hitgroupid, clienthp)
{
	// Set bleed info to true
	BleedInfo[client][enabled]  = true;

	// Add attacker index
	BleedInfo[client][attacker] = attackerid;

	// Set health infos equal to real current player's health value
	BleedInfo[client][health]   = BleedInfo[client][curhealth] = clienthp;

	// Retrieve a hitgroup
	switch (hitgroupid)
	{
		// Take appropriate damage per Y seconds depends on ConVar values
		case head: BleedInfo[client][damage] += GetConVarInt(Bleed_Damage[HEAD]);
		case body: BleedInfo[client][damage] += GetConVarInt(Bleed_Damage[BODY]);
		default:   BleedInfo[client][damage] += GetConVarInt(Bleed_Damage[OTHER]);
	}
}

/* StopBleed()
 *
 * Stops bleeding and removing player from timer queue.
 * -------------------------------------------------------------------------- */
StopBleed(client) BleedInfo[client][enabled] = BleedInfo[client][damage] = false;