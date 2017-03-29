package com.cube.geofencing;

import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.support.annotation.Nullable;
import android.support.v4.app.NotificationCompat;
import android.util.Log;

import com.facebook.react.HeadlessJsTaskService;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.facebook.react.jstasks.HeadlessJsTaskConfig;
import com.google.android.gms.location.Geofence;
import com.google.android.gms.location.GeofencingEvent;

import static com.cube.geofencing.RNRegionMonitorModule.TAG;

/**
 * Service launched when a region transition occurs
 */
public class RNRegionTransitionService extends HeadlessJsTaskService
{
	@Override
	@Nullable
	protected HeadlessJsTaskConfig getTaskConfig(Intent intent)
	{
		if (intent.getExtras() == null)
		{
			return null;
		}

		GeofencingEvent geofencingEvent = GeofencingEvent.fromIntent(intent);

		if (geofencingEvent.hasError())
		{
			// Suppress geofencing event with error
			Log.d(TAG, "Suppress geocoding event with error");
			return null;
		}

		if (!intent.getBooleanExtra("launchHeadless", false))
		{
			showNotification(intent);
			return null;
		}

		NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
		int notificationId = intent.getIntExtra("notificationId", 0);
		if (notificationId != 0)
		{
			notificationManager.cancel("checkInRequest", notificationId);
		}

		WritableMap location = Arguments.createMap();
		location.putDouble("latitude", geofencingEvent.getTriggeringLocation().getLatitude());
		location.putDouble("longitude", geofencingEvent.getTriggeringLocation().getLongitude());

		WritableMap region = Arguments.createMap();
		region.putString("identifier", geofencingEvent.getTriggeringGeofences().get(0).getRequestId());

		WritableArray regionIdentifiers = Arguments.createArray();
		for (Geofence triggered : geofencingEvent.getTriggeringGeofences())
		{
			regionIdentifiers.pushString(triggered.getRequestId());
		}
		region.putArray("identifiers", regionIdentifiers);

		WritableMap jsArgs = Arguments.createMap();
		jsArgs.putMap("location", location);
		jsArgs.putMap("region", region);
		jsArgs.putBoolean("didEnter", geofencingEvent.getGeofenceTransition() == Geofence.GEOFENCE_TRANSITION_ENTER);
		jsArgs.putBoolean("didExit", geofencingEvent.getGeofenceTransition() == Geofence.GEOFENCE_TRANSITION_EXIT);
		jsArgs.putBoolean("didDwell", geofencingEvent.getGeofenceTransition() == Geofence.GEOFENCE_TRANSITION_DWELL);

		Log.d(TAG, "Report geofencing event to JS: " + jsArgs);
		return new HeadlessJsTaskConfig(RNRegionMonitorModule.TRANSITION_TASK_NAME, jsArgs, 0, true);
	}

	private void showNotification(Intent intent)
	{

		String packageName = getApplicationContext().getPackageName();
		int smallIconResId = getApplicationContext().getResources().getIdentifier("ic_notification", "mipmap", packageName);
		if (smallIconResId == 0)
		{
			smallIconResId = getApplicationContext().getResources().getIdentifier("ic_launcher", "mipmap", packageName);

			if (smallIconResId == 0)
			{
				smallIconResId = android.R.drawable.ic_dialog_info;
			}
		}

		int notificationID = (int)System.currentTimeMillis();

		Intent notificationIntent = new Intent(getApplicationContext(), RNRegionTransitionService.class);
		notificationIntent.putExtras(intent);
		notificationIntent.putExtra("launchHeadless", true);
		PendingIntent pendingIntent = PendingIntent.getService(getApplicationContext(), notificationID, notificationIntent, PendingIntent.FLAG_UPDATE_CURRENT);

		Intent yesActionIntent = new Intent(getApplicationContext(), RNRegionTransitionService.class);
		yesActionIntent.putExtras(intent);
		yesActionIntent.putExtra("launchHeadless", true);
		yesActionIntent.putExtra("notificationId", notificationID);
		PendingIntent yesPendingActionIntent = PendingIntent.getService(getApplicationContext(),
		                                                                notificationID,
		                                                                yesActionIntent,
		                                                                PendingIntent.FLAG_UPDATE_CURRENT);

		Intent noActionIntent = new Intent(getApplicationContext(), NotificationCancelReceiver.class);
		noActionIntent.putExtra("notificationId", notificationID);
		PendingIntent noPendingActionIntent = PendingIntent.getBroadcast(getApplicationContext(),
		                                                                 notificationID,
		                                                                 noActionIntent,
		                                                                 PendingIntent.FLAG_UPDATE_CURRENT);

		Notification notification = new NotificationCompat.Builder(getApplicationContext()).setContentTitle("O2 Touch session nearby!")
		                                                                                   .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
		                                                                                   .setPriority(NotificationCompat.PRIORITY_HIGH)
		                                                                                   .setAutoCancel(false)
		                                                                                   .setContentText("Would you like to check in to this session?")
		                                                                                   .setSmallIcon(smallIconResId)
		                                                                                   .addAction(0, "Yes", yesPendingActionIntent)
		                                                                                   .addAction(0, "No", noPendingActionIntent)
		                                                                                   .setVibrate(new long[]{0, 300L})
		                                                                                   .build();

		NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
		notificationManager.notify("checkInRequest", notificationID, notification);
	}
}
