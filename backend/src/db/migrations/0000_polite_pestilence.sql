CREATE TABLE "convoy_members" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"convoy_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"vehicle_id" uuid,
	"role" text DEFAULT 'member' NOT NULL,
	"joined_at" timestamp with time zone DEFAULT now() NOT NULL,
	"left_at" timestamp with time zone,
	"last_known_position" geography(Point, 4326),
	"last_position_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "convoys" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"owner_user_id" uuid NOT NULL,
	"name" text NOT NULL,
	"invite_code" text NOT NULL,
	"status" text DEFAULT 'lobby' NOT NULL,
	"proximity_threshold_m" integer DEFAULT 500 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"started_at" timestamp with time zone,
	"ended_at" timestamp with time zone,
	CONSTRAINT "convoys_invite_code_unique" UNIQUE("invite_code")
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"apple_user_id" text NOT NULL,
	"display_name" text NOT NULL,
	"email" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_apple_user_id_unique" UNIQUE("apple_user_id")
);
--> statement-breakpoint
CREATE TABLE "vehicle_mods" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"vehicle_id" uuid NOT NULL,
	"name" text NOT NULL,
	"description" text,
	"category" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "vehicles" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"make" text NOT NULL,
	"model" text NOT NULL,
	"year" smallint,
	"color" text,
	"photo_url" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "convoy_members" ADD CONSTRAINT "convoy_members_convoy_id_convoys_id_fk" FOREIGN KEY ("convoy_id") REFERENCES "public"."convoys"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "convoy_members" ADD CONSTRAINT "convoy_members_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "convoy_members" ADD CONSTRAINT "convoy_members_vehicle_id_vehicles_id_fk" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "convoys" ADD CONSTRAINT "convoys_owner_user_id_users_id_fk" FOREIGN KEY ("owner_user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "vehicle_mods" ADD CONSTRAINT "vehicle_mods_vehicle_id_vehicles_id_fk" FOREIGN KEY ("vehicle_id") REFERENCES "public"."vehicles"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "vehicles" ADD CONSTRAINT "vehicles_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "convoy_members_convoy_user_unique" ON "convoy_members" USING btree ("convoy_id","user_id");