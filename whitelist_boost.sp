/* 
 * L4D2 Whitelist Weapon Boost + Infinite Ammo (Key X) - Per-Frame Version (High-Performance)
 * Bind: bind x "+wl_boost"
 *
 * Features:
 * - Press X to trigger: increases fire rate / attack frequency for whitelisted guns for 3 seconds
 * - 10-second cooldown
 * - During the skill window: on each shot (weapon_fire), add +N to magazine m_iClip1 to simulate infinite ammo (whitelist only)
 * - Survivors only
 * - Whitelisted weapons only (excluding weapon_melee)
 *
 * Key design points (balancing "very fast" and CPU usage):
 * 1) Acceleration uses PostThinkPost (per-frame) for the strongest effect (scale differences are obvious)
 * 2) Only Hook PostThink during the skill window; Unhook immediately when the window ends (zero overhead outside the window)
 * 3) Whitelist uses StringMap + EntRef caching to avoid per-frame scanning and repeated GetEntityClassname calls
 * 4) Reload detection offsets are lazily cached to avoid per-frame GetEntSendPropOffs calls
 *
 * Compatibility fix:
 * - If triggered from the server console (client=0), only attempt to map to a human player on listen servers
 *
 * Dependencies: SourceMod 1.12+, SDKHooks (included with SourceMod)
 */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
    name        = "L4D2 WL Boost + InfAmmo (Key X) - PerFrame",
    author      = "aesty",
    description = "Press X to trigger whitelist boost (per-frame clamp) + infinite ammo (weapon_fire refunds clip)",
    version     = "2.0.0",
    url         = ""
};

/* ========================= CVAR PARAMETERS ========================= */
ConVar g_cvEnable;         // Master enable switch
ConVar g_cvTeam;           // Affected team (2 = Survivors)

ConVar g_cvScale;          // Remaining time scale (smaller = faster)
ConVar g_cvDuration;       // Duration (seconds)
ConVar g_cvCooldown;       // Cooldown (seconds)

ConVar g_cvRefundPerShot;  // Clip refund per shot (default 1)

/* ========================= STATE ========================= */
float  g_fBoostUntil[MAXPLAYERS + 1]; // Skill window end time
float  g_fNextReady[MAXPLAYERS + 1];  // Next usable time
Handle g_hReadyTimer[MAXPLAYERS + 1]; // Cooldown-complete notification timer
Handle g_hEndTimer[MAXPLAYERS + 1];   // Window-end timer (unhooks PostThink)
bool   g_bThinkHooked[MAXPLAYERS + 1];// Whether PostThink is currently hooked

/* ========================= WHITELIST (StringMap) ========================= */
StringMap g_WeaponWL;

/* ========================= WEAPON ENTITY CACHE (EntRef validation) =========================
 * Purpose: when checking the same weapon entity across multiple frames, avoid repeated
 *          GetEntityClassname + StringMap lookup.
 * Note: entindex can be reused, so EntRef must be used to validate it's the same entity.
 */
#define MAX_EDICTS 2048
bool g_bWepCached[MAX_EDICTS + 1];
bool g_bWepAllowed[MAX_EDICTS + 1];
int  g_iWepEntRef[MAX_EDICTS + 1];

/* ========================= RELOAD CHECK OFFSETS (LAZY CACHE) ========================= */
int g_offInReload    = -2; // -2 = uninitialized
int g_offReloadState = -2; // -2 = uninitialized

/* ========================= COMMON CHECKS ========================= */

bool IsClientEligibleBase(int client)
{
    if (!g_cvEnable.BoolValue) return false;
    if (client <= 0) return false;
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return false;
    if (GetClientTeam(client) != g_cvTeam.IntValue) return false;
    return true;
}

bool IsBoostActive(int client, float now)
{
    return (now < g_fBoostUntil[client]);
}

/* ========================= LISTEN-SERVER HUMAN MAPPING (COMPAT FIX) ========================= */

int FindAnyHumanClientPreferSurvivor()
{
    int fallback = 0;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
            continue;

        if (GetClientTeam(i) == 2) // Prefer Survivors
            return i;

        if (fallback == 0)
            fallback = i;
    }
    return fallback;
}

/* ========================= WHITELIST BUILD ========================= */

void BuildWeaponWhitelist()
{
    if (g_WeaponWL == null)
        g_WeaponWL = new StringMap();
    else
        g_WeaponWL.Clear();

    /* Matches your original whitelist */
    g_WeaponWL.SetValue("weapon_autoshotgun", 1);
    g_WeaponWL.SetValue("weapon_hunting_rifle", 1);
    g_WeaponWL.SetValue("weapon_pistol", 1);
    g_WeaponWL.SetValue("weapon_pistol_magnum", 1);
    g_WeaponWL.SetValue("weapon_pumpshotgun", 1);
    g_WeaponWL.SetValue("weapon_rifle", 1);
    g_WeaponWL.SetValue("weapon_rifle_ak47", 1);
    g_WeaponWL.SetValue("weapon_rifle_desert", 1);
    g_WeaponWL.SetValue("weapon_rifle_m60", 1);
    g_WeaponWL.SetValue("weapon_rifle_sg552", 1);
    g_WeaponWL.SetValue("weapon_shotgun_chrome", 1);
    g_WeaponWL.SetValue("weapon_shotgun_spas", 1);
    g_WeaponWL.SetValue("weapon_smg", 1);
    g_WeaponWL.SetValue("weapon_smg_mp5", 1);
    g_WeaponWL.SetValue("weapon_smg_silenced", 1);
    g_WeaponWL.SetValue("weapon_sniper_awp", 1);
    g_WeaponWL.SetValue("weapon_sniper_military", 1);
    g_WeaponWL.SetValue("weapon_sniper_scout", 1);
}

/* Whitelist query (with entity cache) */
bool IsWeaponWhitelistedCached(int wep)
{
    if (wep <= MaxClients || !IsValidEdict(wep)) return false;
    if (wep < 0 || wep > MAX_EDICTS) return false;

    int ref = EntIndexToEntRef(wep);

    if (g_bWepCached[wep] && g_iWepEntRef[wep] == ref)
        return g_bWepAllowed[wep];

    char cls[64];
    bool allowed = false;

    if (GetEntityClassname(wep, cls, sizeof(cls)) && g_WeaponWL != null)
    {
        int dummy;
        allowed = g_WeaponWL.GetValue(cls, dummy);
    }

    g_bWepCached[wep]  = true;
    g_iWepEntRef[wep]  = ref;
    g_bWepAllowed[wep] = allowed;

    return allowed;
}

/* Reload check (lazy cached offsets) */
bool IsReloading(int wep)
{
    if (wep <= MaxClients || !IsValidEdict(wep)) return false;

    if (g_offInReload == -2)
        g_offInReload = GetEntSendPropOffs(wep, "m_bInReload");

    if (g_offReloadState == -2)
        g_offReloadState = GetEntSendPropOffs(wep, "m_reloadState");

    if (g_offInReload != -1 && view_as<bool>(GetEntData(wep, g_offInReload, 1)))
        return true;

    if (g_offReloadState != -1 && GetEntData(wep, g_offReloadState, 4) != 0)
        return true;

    return false;
}

/* Only shorten future timestamps; never extend */
stock void ClampFutureTimeNonExtend(int ent, const char[] prop, float now, float scale, float minRemain = 0.0)
{
    float t = GetEntPropFloat(ent, Prop_Send, prop);
    if (t <= now) return;

    float rem    = t - now;
    float target = rem * scale;

    if (target < minRemain) target = minRemain;
    if (target >= rem - 0.001) return;

    SetEntPropFloat(ent, Prop_Send, prop, now + target);
}

/* ========================= COOLDOWN NOTICE / WINDOW END ========================= */

public Action Timer_Ready(Handle timer, any client)
{
    if (client <= 0 || client > MaxClients) return Plugin_Stop;
    g_hReadyTimer[client] = null;

    if (!IsClientInGame(client)) return Plugin_Stop;
    if (!g_cvEnable.BoolValue) return Plugin_Stop;

    float now = GetGameTime();
    if (now >= g_fNextReady[client])
        PrintToChat(client, "[WL Boost] Cooldown ready");

    return Plugin_Stop;
}

/* Skill window end: unhook PostThink (key CPU-saving point) */
public Action Timer_EndBoost(Handle timer, any client)
{
    if (client <= 0 || client > MaxClients) return Plugin_Stop;
    g_hEndTimer[client] = null;

    if (!IsClientInGame(client)) return Plugin_Stop;

    if (g_bThinkHooked[client])
    {
        SDKUnhook(client, SDKHook_PostThinkPost, PostThinkClamp);
        g_bThinkHooked[client] = false;
    }
    return Plugin_Stop;
}

/* ========================= TRIGGER COMMAND (X) ========================= */

public Action Cmd_WLBoost(int client, int args)
{
    // If triggered from the server console (client=0), only attempt to map to a human player on listen servers
    if (client <= 0)
    {
        if (IsDedicatedServer())
            return Plugin_Handled;

        int mapped = FindAnyHumanClientPreferSurvivor();
        if (mapped == 0)
            return Plugin_Handled;

        client = mapped;
    }

    if (!IsClientInGame(client)) return Plugin_Handled;
    if (!g_cvEnable.BoolValue)   return Plugin_Handled;

    if (!IsPlayerAlive(client))
    {
        PrintToChat(client, "[WL Boost] Trigger failed: you are dead");
        return Plugin_Handled;
    }

    if (GetClientTeam(client) != g_cvTeam.IntValue)
    {
        PrintToChat(client, "[WL Boost] Trigger failed: team not allowed");
        return Plugin_Handled;
    }

    float now = GetGameTime();
    if (now < g_fNextReady[client])
    {
        PrintToChat(client, "[WL Boost] On cooldown: %.1f seconds", g_fNextReady[client] - now);
        return Plugin_Handled;
    }

    /* Must be holding a whitelisted weapon to trigger */
    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsWeaponWhitelistedCached(wep))
    {
        PrintToChat(client, "[WL Boost] Trigger failed: current weapon is not whitelisted");
        return Plugin_Handled;
    }

    /* Block triggering while reloading (avoid interfering with reload flow) */
    if (IsReloading(wep))
    {
        PrintToChat(client, "[WL Boost] Trigger failed: cannot trigger while reloading");
        return Plugin_Handled;
    }

    float duration = g_cvDuration.FloatValue;
    float cd       = g_cvCooldown.FloatValue;
    float scale    = g_cvScale.FloatValue;

    g_fBoostUntil[client] = now + duration;
    g_fNextReady[client]  = now + cd;

    PrintToChat(client, "[WL Boost] Triggered: %.1f seconds (scale=%.3f) + infinite ammo, cooldown %.1f seconds", duration, scale, cd);

    /* Cooldown notification timer */
    if (g_hReadyTimer[client] != null) { delete g_hReadyTimer[client]; g_hReadyTimer[client] = null; }
    g_hReadyTimer[client] = CreateTimer(cd, Timer_Ready, client);

    /* End timer: unhook when time is up */
    if (g_hEndTimer[client] != null) { delete g_hEndTimer[client]; g_hEndTimer[client] = null; }
    g_hEndTimer[client] = CreateTimer(duration, Timer_EndBoost, client);

    /* Hook PostThink only during the skill window (save CPU) */
    if (!g_bThinkHooked[client])
    {
        SDKHook(client, SDKHook_PostThinkPost, PostThinkClamp);
        g_bThinkHooked[client] = true;
    }

    return Plugin_Handled;
}

public Action Cmd_WLBoostStop(int client, int args)
{
    /* No action on key release (placeholder) */
    return Plugin_Handled;
}

/* ========================= PER-FRAME BOOST (RUNS ONLY DURING WINDOW) ========================= */

public void PostThinkClamp(int client)
{
    if (!IsClientEligibleBase(client))
        return;

    float now = GetGameTime();

    /* Window expired: safety unhook (converges automatically even if timers fail) */
    if (!IsBoostActive(client, now))
    {
        if (g_bThinkHooked[client])
        {
            SDKUnhook(client, SDKHook_PostThinkPost, PostThinkClamp);
            g_bThinkHooked[client] = false;
        }
        return;
    }

    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsWeaponWhitelistedCached(wep))
        return;

    if (IsReloading(wep))
        return;

    float scale = g_cvScale.FloatValue;

    ClampFutureTimeNonExtend(client, "m_flNextAttack", now, scale, 0.0);
    ClampFutureTimeNonExtend(wep,    "m_flNextPrimaryAttack",   now, scale, 0.0);
    ClampFutureTimeNonExtend(wep,    "m_flNextSecondaryAttack", now, scale, 0.0);
}

/* ========================= INFINITE AMMO: REFUND CLIP ON FIRE EVENT ========================= */

public void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsClientEligibleBase(client))
        return;

    float now = GetGameTime();
    if (!IsBoostActive(client, now))
        return;

    int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsWeaponWhitelistedCached(wep))
        return;

    /* No refund while reloading, to avoid breaking reload cadence */
    if (IsReloading(wep))
        return;

    int add = g_cvRefundPerShot.IntValue;
    if (add <= 0)
        return;

    int clip = GetEntProp(wep, Prop_Send, "m_iClip1");
    if (clip < 0)
        return; // Non-clip weapons / special cases are ignored

    SetEntProp(wep, Prop_Send, "m_iClip1", clip + add);
}

/* ========================= LIFECYCLE ========================= */

public void OnPluginStart()
{
    g_cvEnable        = CreateConVar("sm_wlboost_enable",   "1",    "Enable plugin (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvTeam          = CreateConVar("sm_wlboost_team",     "2",    "Affected team (2=Survivors)", FCVAR_NOTIFY, true, 0.0, true, 3.0);

    g_cvScale         = CreateConVar("sm_wlboost_scale",    "0.25", "Remaining time scale (smaller = faster)", FCVAR_NOTIFY, true, 0.05, true, 1.0);
    g_cvDuration      = CreateConVar("sm_wlboost_duration", "3.0",  "Duration (seconds)", FCVAR_NOTIFY, true, 0.1, true, 60.0);
    g_cvCooldown      = CreateConVar("sm_wlboost_cooldown", "10.0", "Cooldown (seconds)", FCVAR_NOTIFY, true, 0.1, true, 300.0);

    g_cvRefundPerShot = CreateConVar("sm_wlboost_refund", "1", "Clip rounds refunded per shot during the window (clip1)", FCVAR_NOTIFY, true, 0.0, true, 10.0);

    AutoExecConfig(true, "plugin_wlboost_keyx_perframe_infammo");

    BuildWeaponWhitelist();

    RegConsoleCmd("sm_wlboost", Cmd_WLBoost);
    RegConsoleCmd("+wl_boost",  Cmd_WLBoost);
    RegConsoleCmd("-wl_boost",  Cmd_WLBoostStop);

    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);

    for (int i = 1; i <= MaxClients; i++)
    {
        g_fBoostUntil[i]  = 0.0;
        g_fNextReady[i]   = 0.0;
        g_hReadyTimer[i]  = null;
        g_hEndTimer[i]    = null;
        g_bThinkHooked[i] = false;
    }
}

public void OnClientPutInServer(int client)
{
    g_fBoostUntil[client]  = 0.0;
    g_fNextReady[client]   = 0.0;

    if (g_hReadyTimer[client] != null) { delete g_hReadyTimer[client]; g_hReadyTimer[client] = null; }
    if (g_hEndTimer[client] != null)   { delete g_hEndTimer[client];   g_hEndTimer[client]   = null; }

    /* Note: PostThink is NOT hooked here to avoid permanent overhead; it is hooked only during the active window */
    g_bThinkHooked[client] = false;
}

public void OnClientDisconnect(int client)
{
    if (g_bThinkHooked[client])
    {
        SDKUnhook(client, SDKHook_PostThinkPost, PostThinkClamp);
        g_bThinkHooked[client] = false;
    }

    if (g_hReadyTimer[client] != null) { delete g_hReadyTimer[client]; g_hReadyTimer[client] = null; }
    if (g_hEndTimer[client] != null)   { delete g_hEndTimer[client];   g_hEndTimer[client]   = null; }

    g_fBoostUntil[client] = 0.0;
    g_fNextReady[client]  = 0.0;
}
