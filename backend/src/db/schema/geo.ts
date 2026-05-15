import { customType } from 'drizzle-orm/pg-core';

// PostGIS geography(Point, 4326) — stored as EWKB hex on read,
// inserted via SQL helpers like ST_SetSRID(ST_MakePoint(lng, lat), 4326).
// The runtime services own the EWKT/EWKB conversion; the schema only declares
// the column type so migrations produce the right DDL.
export const geographyPoint = customType<{ data: string }>({
  dataType() {
    return 'geography(Point, 4326)';
  },
});
