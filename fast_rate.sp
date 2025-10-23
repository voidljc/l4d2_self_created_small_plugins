/* 依赖：SourceMod 1.12+，SDKHooks（随 SM 自带） */

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

public Plugin myinfo =
{
    name        = "FastRate (Crouch Booster)",
    author      = "you",
    description = "Speed up actions while crouching by clamping future timers; melee safe-guard",
    version     = "1.3",
    url         = ""
};

/* ========================= CVAR ========================= */
ConVar g_cvEnable;        // 开关
ConVar g_cvScale;         // 速度：剩余时长乘以 scale (0~1)
ConVar g_cvTeam;          // 生效队伍（2=生还者）
ConVar g_cvSlotMode;      // 0=slot0, 1=active
ConVar g_cvNeedDuck;      // 需要 IN_DUCK
ConVar g_cvUseFLDuck;     // 使用 FL_DUCKING 判定

ConVar g_cvAffectFire;    // 影响射击/投掷
ConVar g_cvAffectReload;  // 影响换弹
ConVar g_cvAffectShove;   // 影响推人

ConVar g_cvMeleeMinRem;   // 近战最小剩余冷却（秒）
ConVar g_cvWhitelist;     // 武器白名单（空=全部）

ArrayList g_Whitelist;

/* ========================= 工具 ========================= */

// 只缩短未来时间：target = max(rem*scale, minRemain)
// 若 target >= rem（说明会延长或无变化），则不写回
stock void ClampFutureTimeNonExtend(int ent, const char[] prop, float now, float scale, float minRemain = 0.0)
{
    float t = GetEntPropFloat(ent, Prop_Send, prop);
    if (t <= now) return;

    float rem    = t - now;
    float target = rem * scale;
    if (target < minRemain) target = minRemain;

    // 避免延长或抖动（只在“明显更短”时写回）
    if (target >= rem - 0.001) return;

    SetEntPropFloat(ent, Prop_Send, prop, now + target);
}

stock bool SplitStringEx(const char[] src, const char[] delim, char[] outToken, int outMax, int &start)
{
    int len = strlen(src);
    if (start >= len) return false;
    int dlen = strlen(delim), i = start, j = 0;
    while (i < len)
    {
        if (dlen && strncmp(src[i], delim, dlen) == 0) break;
        if (j < outMax - 1) outToken[j++] = src[i];
        i++;
    }
    outToken[j] = '\0';
    start = (i < len) ? i + dlen : len;
    return true;
}

void RebuildWhitelist()
{
    if (g_Whitelist == null) g_Whitelist = new ArrayList(ByteCountToCells(64));
    g_Whitelist.Clear();

    char buf[512];
    g_cvWhitelist.GetString(buf, sizeof(buf));
    if (!buf[0]) return;

    char token[64]; int pos = 0;
    while (SplitStringEx(buf, ",", token, sizeof(token), pos))
    {
        TrimString(token);
        if (token[0]) g_Whitelist.PushString(token);
    }
}

public void OnWhitelistChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RebuildWhitelist();
}

bool IsWeaponWhitelisted(int wep)
{
    if (g_Whitelist == null || g_Whitelist.Length == 0) return true;
    char cls[64];
    if (!GetEntityClassname(wep, cls, sizeof(cls))) return false;
    for (int i = 0; i < g_Whitelist.Length; i++)
    {
        char w[64]; g_Whitelist.GetString(i, w, sizeof(w));
        if (StrEqual(cls, w, false)) return true;
    }
    return false;
}

stock bool GetWeaponClassName(int wep, char[] cls, int maxlen)
{
    if (wep <= MaxClients || !IsValidEdict(wep)) return false;
    return GetEntityClassname(wep, cls, maxlen);
}

/* ========================= 初始化 ========================= */

public void OnPluginStart()
{
    g_cvEnable     = CreateConVar("sm_crouchboost_enable", "1",   "Enable plugin (1/0)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvScale      = CreateConVar("sm_crouchboost_scale",  "0.50","Remaining time scale while crouching (0~1)", FCVAR_NOTIFY, true, 0.05, true, 1.0);
    g_cvTeam       = CreateConVar("sm_crouchboost_team",   "2",   "Team to affect (2=Survivors)", FCVAR_NOTIFY, true, 0.0, true, 3.0);
    g_cvSlotMode   = CreateConVar("sm_crouchboost_slot",   "1",   "Weapon target: 0=slot0, 1=active", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvNeedDuck   = CreateConVar("sm_crouchboost_needduck","1",  "Require IN_DUCK pressed (ignored if FL_DUCKING mode)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvUseFLDuck  = CreateConVar("sm_crouchboost_flduck", "0",   "Use FL_DUCKING instead of IN_DUCK", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvAffectFire   = CreateConVar("sm_crouchboost_fire",   "1", "Affect fire/throw timers", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAffectReload = CreateConVar("sm_crouchboost_reload", "1", "Affect reload timers",    FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvAffectShove  = CreateConVar("sm_crouchboost_shove",  "1", "Affect shove cooldown",   FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_cvMeleeMinRem  = CreateConVar("sm_crouchboost_melee_minrem", "0.22", "Melee minimum remaining cooldown (seconds)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvWhitelist    = CreateConVar("sm_crouchboost_weapons","",    "Comma separated weapon class whitelist (empty=all)", FCVAR_NOTIFY);

    AutoExecConfig(true, "plugin_crouchboost");

    HookConVarChange(g_cvWhitelist, OnWhitelistChanged);
    RebuildWhitelist();

    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i))
            SDKHook(i, SDKHook_PostThinkPost, PostThinkClamp);
}

public void OnClientPutInServer(int client) { SDKHook(client, SDKHook_PostThinkPost, PostThinkClamp); }
public void OnClientDisconnect(int client)  { SDKUnhook(client, SDKHook_PostThinkPost, PostThinkClamp); }

/* ========================= 判定与封装 ========================= */

bool IsClientEligible(int client)
{
    if (!g_cvEnable.BoolValue) return false;
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return false;
    if (GetClientTeam(client) != g_cvTeam.IntValue) return false;
    return true;
}

bool IsCrouchActive(int client)
{
    int buttons = GetClientButtons(client);

    if (g_cvUseFLDuck.BoolValue)
    {
        if ((GetEntityFlags(client) & FL_DUCKING) == 0)
            return false;
    }
    else if (g_cvNeedDuck.BoolValue)
    {
        if ((buttons & IN_DUCK) == 0)
            return false;
    }

    // 禁止移动/跳跃时才算触发
    if ((buttons & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)) != 0)
        return false;

    // 玩家正在按 R 主动换弹则直接不触发
    if (buttons & IN_RELOAD)
        return false;

    return true;
}

int GetTargetWeapon(int client)
{
    int wep = (g_cvSlotMode.IntValue == 0)
        ? GetPlayerWeaponSlot(client, 0)
        : GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (wep > MaxClients && IsValidEdict(wep)) return wep;
    return -1;
}

bool IsReloading(int wep)
{
    if (wep <= MaxClients || !IsValidEdict(wep)) return false;

    int offs = GetEntSendPropOffs(wep, "m_bInReload");
    if (offs != -1 && view_as<bool>(GetEntData(wep, offs, 1)))
        return true;

    int st_offs = GetEntSendPropOffs(wep, "m_reloadState"); // 霰弹逐发
    if (st_offs != -1 && GetEntData(wep, st_offs, 4) != 0)
        return true;

    return false;
}

bool IsMelee(int wep)
{
    if (wep <= MaxClients || !IsValidEdict(wep)) return false;
    char wcls[64];
    if (!GetWeaponClassName(wep, wcls, sizeof(wcls))) return false;
    return StrEqual(wcls, "weapon_melee", false);
}

void ClampPlayerLevel(int client, float now, float scale, bool isMelee)
{
    if (!(g_cvAffectFire.BoolValue || g_cvAffectReload.BoolValue)) return;

    float minRemP = isMelee ? g_cvMeleeMinRem.FloatValue : 0.0;
    ClampFutureTimeNonExtend(client, "m_flNextAttack", now, scale, minRemP);
}

void ClampWeaponLevel(int wep, float now, float scale, bool isMelee)
{
    if (wep <= MaxClients || !IsValidEdict(wep)) return;
    if (!IsWeaponWhitelisted(wep)) return;
    if (!(g_cvAffectFire.BoolValue || g_cvAffectReload.BoolValue)) return;

    float minRemW = isMelee ? g_cvMeleeMinRem.FloatValue : 0.0;
    ClampFutureTimeNonExtend(wep, "m_flNextPrimaryAttack",   now, scale, minRemW);
    ClampFutureTimeNonExtend(wep, "m_flNextSecondaryAttack", now, scale, minRemW);
}

void ClampShove(int client, float now, float scale)
{
    if (!g_cvAffectShove.BoolValue) return;
    ClampFutureTimeNonExtend(client, "m_flNextShoveTime", now, scale, 0.0);
}

void ProcessClient(int client)
{
    if (!IsClientEligible(client)) return;
    if (!IsCrouchActive(client))   return;

    float now   = GetGameTime();
    float scale = g_cvScale.FloatValue;

    int wep = GetTargetWeapon(client);
    bool hasWeapon = (wep != -1);

    // 若当前武器处于（显式或逐发）换弹中，则不做加速
    if (hasWeapon && IsReloading(wep)) return;

    bool isMelee = hasWeapon ? IsMelee(wep) : false;

    // 1) 玩家层：开火/换弹总门控
    ClampPlayerLevel(client, now, scale, isMelee);

    // 2) 推人 CD
    ClampShove(client, now, scale);

    // 3) 武器层：主/副攻击
    if (hasWeapon)
        ClampWeaponLevel(wep, now, scale, isMelee);
}

/* ========================= 主钩子 ========================= */

public void PostThinkClamp(int client)
{
    ProcessClient(client);
}
