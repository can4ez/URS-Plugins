#pragma semicolon 1 
#pragma tabsize 0
#pragma newdecls required

#include <sourcemod> 

#define REWARD_CODE	"Reward_Other"
#define REWARD_COST 1

public Plugin myinfo =  { name = "[ URS ] Test Module" };


public bool URS_OnClientChoseReward(int iClient, const char[] sReward, int &iCost) {
	
	if (!strcmp(REWARD_CODE, sReward)) {
		
		iCost = REWARD_COST;
		
		return true;
		
	}
	
	return false;
	
} 