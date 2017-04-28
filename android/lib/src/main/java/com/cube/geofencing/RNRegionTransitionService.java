package com.cube.geofencing;

import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.support.annotation.Nullable;
import android.support.v4.app.NotificationCompat;
import android.util.Log;

import com.cube.geofencing.model.MonitoredRegion;
import com.cube.geofencing.model.PersistableData;
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
	public static final String NOTIFICATION_TAG = "transition_notif_tag";
	public static final String NOTIFICATION_ID_KEY = "notificationId";
	private static final String HEADLESS_KEY = "launchHeadless";

	@Override
	@Nullable
	protected HeadlessJsTaskConfig getTaskConfig(Intent intent)
	{
		if (intent.getExtras() == null)
		{
			return null;
		}

		GeofencingEvent geofencingEvent = GeofencingEvent.fromIntent(intent);

		if (geofencingEvent.hasError() || geofencingEvent.getTriggeringGeofences() == null || geofencingEvent.getTriggeringGeofences().isEmpty())
		{
			// Suppress geofencing event with error
			Log.w(TAG, "Suppress geofencing event with error");
			return null;
		}

		if (!intent.getBooleanExtra(HEADLESS_KEY, false))
		{
			Log.d(TAG, "Received geofencing event, but not sending to JS, creating notification if region is active...");
			String eventId = geofencingEvent.getTriggeringGeofences().get(0).getRequestId();
			if (eventId != null)
			{
				Log.d(TAG, "Got event Id, now loading persisted data...");
				PersistableData data = PersistableData.load(getApplicationContext());
				MonitoredRegion region = data.getRegion(eventId);
				Log.d(TAG, "Got region: " + region);
				if (region != null && region.isActive())
				{
					Log.d(TAG, "Region is active, show notification!");
					showNotification(intent, region);
				}
				else
				{
					Log.d(TAG, "Region is not active");
				}
			}
			else
			{
				Log.w(TAG, "No eventId associated with geofencing event...");
			}
			return null;
		}

		NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
		int notificationId = intent.getIntExtra(NOTIFICATION_ID_KEY, 0);
		if (notificationId != 0)
		{
			notificationManager.cancel(NOTIFICATION_TAG, notificationId);
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

	private void showNotification(Intent intent, MonitoredRegion region)
	{

		String packageName = getApplicationContext().getPackageName();
		int smallIconResId = getApplicationContext().getResources().getIdentifier("ic_notification", "mipmap", packageName);
		int largeIconResId = getApplicationContext().getResources().getIdentifier("ic_launcher", "mipmap", packageName);

		if (smallIconResId == 0)
		{
			smallIconResId = getApplicationContext().getResources().getIdentifier("ic_launcher", "mipmap", packageName);

			if (smallIconResId == 0)
			{
				smallIconResId = android.R.drawable.ic_dialog_info;
			}
		}

		Bitmap largeIconBitmap = BitmapFactory.decodeResource(getApplicationContext().getResources(), largeIconResId);

		int notificationID = (int)System.currentTimeMillis();
		try
		{
			notificationID = Integer.parseInt(region.getId());
		}
		catch (Exception ex)
		{
			// ignore
		}

		Intent notificationIntent = new Intent(getApplicationContext(), RNRegionTransitionService.class);
		notificationIntent.putExtras(intent);
		notificationIntent.putExtra(HEADLESS_KEY, true);
		PendingIntent pendingIntent = PendingIntent.getService(getApplicationContext(), notificationID, notificationIntent, PendingIntent.FLAG_UPDATE_CURRENT);

		Intent yesActionIntent = new Intent(getApplicationContext(), RNRegionTransitionService.class);
		yesActionIntent.putExtras(intent);
		yesActionIntent.putExtra(HEADLESS_KEY, true);
		yesActionIntent.putExtra(NOTIFICATION_ID_KEY, notificationID);
		PendingIntent yesPendingActionIntent = PendingIntent.getService(getApplicationContext(),
		                                                                notificationID,
		                                                                yesActionIntent,
		                                                                PendingIntent.FLAG_UPDATE_CURRENT);

		Intent noActionIntent = new Intent(getApplicationContext(), NotificationCancelReceiver.class);
		noActionIntent.putExtra(NOTIFICATION_ID_KEY, notificationID);
		PendingIntent noPendingActionIntent = PendingIntent.getBroadcast(getApplicationContext(),
		                                                                 notificationID,
		                                                                 noActionIntent,
		                                                                 PendingIntent.FLAG_UPDATE_CURRENT);

		// TODO: Don't hardcode these strings
		NotificationCompat.Builder notificationBuilder = new NotificationCompat.Builder(getApplicationContext()).setContentTitle("O2 Touch session nearby!")
		                                                                                                        .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
		                                                                                                        .setPriority(NotificationCompat.PRIORITY_MAX)
		                                                                                                        .setWhen(0)
		                                                                                                        .setAutoCancel(false)
		                                                                                                        .setContentText("Would you like to check in to this session?")
		                                                                                                        .setSmallIcon(smallIconResId)
		                                                                                                        .setContentIntent(pendingIntent)
		                                                                                                        .addAction(0, "Yes", yesPendingActionIntent)
		                                                                                                        .addAction(0, "No", noPendingActionIntent)
		                                                                                                        .setVibrate(new long[]{0, 300L});
		if (largeIconResId != 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP)
		{
			notificationBuilder.setLargeIcon(largeIconBitmap);
		}

		NotificationManager notificationManager = (NotificationManager) getApplicationContext().getSystemService(Context.NOTIFICATION_SERVICE);
		notificationManager.notify(NOTIFICATION_TAG, notificationID, notificationBuilder.build());
	}
}
