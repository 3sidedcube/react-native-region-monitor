package com.cube.geofencing.model;

import com.esotericsoftware.kryo.serializers.TaggedFieldSerializer;
import com.google.android.gms.location.Geofence;

/**
 * Created by tim on 19/01/2017.
 */
public class MonitoredRegion
{
	@TaggedFieldSerializer.Tag(1)
	private String id;
	@TaggedFieldSerializer.Tag(2)
	private double latitude;
	@TaggedFieldSerializer.Tag(3)
	private double longitude;
	@TaggedFieldSerializer.Tag(4)
	private int radius;
	@TaggedFieldSerializer.Tag(5)
	private Long startTime;
	@TaggedFieldSerializer.Tag(6)
	private Long endTime;

	public MonitoredRegion()
	{}

	public MonitoredRegion(String id, double latitude, double longitude, int radius)
	{
		this(id, latitude, longitude, radius, null, null);
	}

	public MonitoredRegion(String id, double latitude, double longitude, int radius, Long startTime, Long endTime)
	{
		this.id = id;
		this.latitude = latitude;
		this.longitude = longitude;
		this.radius = radius;
		this.startTime = startTime;
		this.endTime = endTime;
	}

	public Geofence createGeofence()
	{
		return new Geofence.Builder().setRequestId(id)
		                             .setCircularRegion(latitude, longitude, radius)
		                             .setTransitionTypes(Geofence.GEOFENCE_TRANSITION_ENTER | Geofence.GEOFENCE_TRANSITION_DWELL | Geofence.GEOFENCE_TRANSITION_EXIT)
		                             .setLoiteringDelay(60000)
		                             .setExpirationDuration(endTime != null ? (endTime - System.currentTimeMillis()) : Geofence.NEVER_EXPIRE)
		                             .build();
	}

	public String getId()
	{
		return id;
	}

	public double getLatitude()
	{
		return latitude;
	}

	public double getLongitude()
	{
		return longitude;
	}

	public int getRadius()
	{
		return radius;
	}

	public boolean isActive()
	{
		return isActiveAt(System.currentTimeMillis());
	}

	public boolean isActiveAt(long time)
	{
		return (startTime == null || time >= startTime) && (endTime == null || time < endTime);
	}
}
