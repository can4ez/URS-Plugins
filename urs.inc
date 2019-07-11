/*
**
*/
#if defined _URS_included
 #endinput
#endif
#define _URS_included


forward bool URS_OnClientChoseReward(int iClient, const char[] sReward,int &iCost);


public SharedPlugin __pl_URS =
{
	name = "[ URS ]",
	file = "urs.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_URS_SetNTVOptional()
{
	MarkNativeAsOptional("");
}
#endif