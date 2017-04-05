package com.cube.geofencing;

import android.app.NotificationManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Created by tim on 29/03/2017.
 */
public class NotificationCancelReceiver extends BroadcastReceiver
{
	@Override
	public void onReceive(Context context, Intent intent)
	{
		//Cancel your ongoing Notification
		Log.d("RNRM", "NotificationCancelReceiver " + intent.getExtras());

		NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
		int notificationId = intent.getIntExtra(RNRegionTransitionService.NOTIFICATION_ID_KEY, 0);
		if (notificationId != 0)
		{
			notificationManager.cancel(RNRegionTransitionService.NOTIFICATION_TAG, notificationId);
		}
	}
}
