#if defined _as_dr_queue_included
	#endinput
#endif
#define _as_dr_queue_included

native int dr_getPosInQueue(int client);
native int dr_getClientByPosInQueue(int position);