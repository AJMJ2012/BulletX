version "4.0.0"

// Adapted from the Bullet-Z resource mod
// Since there is no way to catch every LineAttack call, we gotta make do. :/
// Can't reliably determine hitscan damage without WorldThingDamaged, but that doesn't tell for missed attacks. For now, it uses a user configurable damage.
// This will break hitscans with non standard damage.
// This must be loaded last.
// All puffs and blood are also replaced with my ImpactX mod.

class BulletX_Puff_Base : Actor {
	int baseDamage;
	Default {
		-BLOODSPLATTER;
		-RANDOMIZE;
		+ALWAYSPUFF;
		+BLOODLESSIMPACT;
		+HITTRACER;
		+NOBLOOD;
		+NODECAL;
		+NOINTERACTION;
		+NOTIMEFREEZE;
		+PUFFGETSOWNER;
		+PUFFONACTORS;
		+SKYEXPLODE;
		VSpeed 0;
		Radius 0;
		Height 0;
	}

	override int DoSpecialDamage(Actor target, int damage, Name damagetype) {
		self.SetDamage(Super.DoSpecialDamage(target, damage, damagetype)); // Get damage that would have been dealt.
		self.damagetype = damagetype;
		return 0; // Don't want this dealing the damage.
	}

	override void PostBeginPlay() {
		Super.PostBeginPlay();
		if (target != null) {
			Vector3 oldPos = pos;
			if (target.bMISSILE && Distance2D(target) <= 1) { return; } // A_Tracer Fix
			float attackzoffset = target.height / 2.0;
			PlayerPawn player = PlayerPawn(target);
			if (player != null) {
				attackzoffset += player.AttackZOffset;
			}
			self.SetOrigin((pos.x, pos.y, pos.z - attackzoffset), false); // Fix Z position for calculations
			pitch = target.PitchTo(self);
			angle = target.AngleTo(self);
			double angleOffset = (angle - target.angle);
			double pitchOffset = (pitch - target.pitch);
			double distance = Distance3D(target);
			self.SetOrigin(oldPos, false); // Restore position

			double meleeRange = target.MeleeRange + 22 + target.Vel.Length(); // Velocity is workaround for melee firing bullets when moving around
			bool isMelee = InStateSequence(ResolveState("Melee"), CurState);
			bool isMeleeDamage = damagetype == "Melee";
			if (isMelee || isMeleeDamage || distance <= meleeRange) { // Fix melee
				target.A_CustomBulletAttack(angleOffset, pitchOffset, 1, damage, (isMelee ? "ImpactXMelee" : "ImpactX"), distance + 8, CBAF_AIMFACING|CBAF_NORANDOM|CBAF_EXPLICITANGLE|CBAF_NORANDOMPUFFZ);
			}
			else {
				Actor oldTargetTarget = target.target;
				target.target = self;
				let bullet = BulletX_Bullet(target.A_SpawnProjectile("BulletX_Bullet"));
				if (damage > 0) {
					bullet.bulletDamage = damage;
				}
				else {
					bullet.bulletDamage = Max(1, (target.player ? CVar.GetCVar("bx_fallbackplayerdamage").GetInt() * Random[GunShot](1, 3) : CVar.GetCVar("bx_fallbackenemydamage").GetInt() * Random[GunShot](1, 5)));
				}
				bullet.distanceToTravel = distance;
				bullet.pitch = pitch;
				target.target = oldTargetTarget;
			}
		}
	}

	States {
		Spawn:
			TNT1 A 4 NoDelay;
			Stop;
		Melee:
			TNT1 A 4;
			Stop;
		Death:
			TNT1 A 4;
			Stop;
	}
}

class BulletX_Base : FastProjectile {
	Default {
		Height 4;
		Radius 2;
		Speed 1;
		Projectile;
		+DONTBLAST;
		+DONTREFLECT;
	}
}

class BulletX_Bullet : BulletX_Base {
	double distanceToTravel;
	Vector3 startPos;
	Actor startMarker;
	int bulletSpeed;
	int bulletDamage;
	Array<Actor> children;

	Default {
		Damage (1); // Needed for DoSpecialDamage
		Friction (59392.0 / 65535.0); // Default Friction
		Scale 0.25;
	}

	override int DoSpecialDamage(Actor target, int damage, Name damagetype) {
		return bulletDamage > 0 ? bulletDamage : 4 * Random[GunShot](1, 4);
	}

	bool OnFloor() {
		return pos.Z <= floorZ || bOnMObj;
	}

	override void PostBeginPlay() {
		startPos = pos;
		startMarker = Spawn("Actor", startPos);
		startMarker.bNOINTERACTION = true;

		Super.PostBeginPlay();
		bulletSpeed = Max(32, CVar.FindCVar("bx_speed").GetInt());
		A_ScaleVelocity(bulletSpeed);

		if (CVar.FindCVar("bx_tracerrounds").GetBool()) {
			children.Push(A_SpawnProjectile("BulletX_Glow", 0));
			children.Push(A_SpawnProjectile("BulletX_Trail", 0));
		}
		if (CVar.FindCVar("bx_vaportrails").GetBool()) {
			children.Push(A_SpawnProjectile("BulletX_Trail2", 0));
		}
		for (int i = 0; i < children.Size(); i++) {
			if (children[i] != null) {
				children[i].SetOrigin(pos, false);
				children[i].pitch = pitch;
				children[i].angle = angle;
				children[i].Vel = Vel;
			}
		}
	}

	override void Tick() {
		Super.Tick();
		if (!Level.isFrozen() && startMarker != null && Distance3D(startMarker) > max(2048, distanceToTravel)) { // Out of range bullets will be subject to gravity rather than just disappear or live forever
			bNOGRAVITY = false;
			Vel.x *= 1.0 - (1.0 / bulletSpeed);
			Vel.y *= 1.0 - (1.0 / bulletSpeed);
			Vel.z *= 1.0 - (1.0 / bulletSpeed);
			if (!OnFloor()) {
				Vel.z -= gravity;
			}
			pitch = PitchFromVel();
			for (int i = 0; i < children.Size(); i++) {
				if (children[i] != null) {
					children[i].SetOrigin(pos - vel, true);
					children[i].bNOGRAVITY = bNOGRAVITY;
					children[i].Vel = Vel;
					children[i].pitch = pitch;
					children[i].SetStateLabel("Death");
				}
			}
		}
	}

	override void OnDestroy() {
		for (int i = 0; i < children.Size(); i++) {
			if (children[i] != null) {
				children[i].Vel = (0,0,0);
				children[i].SetStateLabel("Death");
			}
		}
		if (startMarker != null) startMarker.Destroy();
		Super.OnDestroy();
	}

	Default {
		+BLOODSPLATTER;
		+GETOWNER;
		Decal "BulletChip";
	}
	States {
		Spawn:
			PUFF A 4 Bright;
			Wait;
		Crash:
		Death:
			PUFF A 1 {
				A_SpawnProjectile("ImpactX", 0);
			}
			Stop;
		XDeath:
			PUFF A 1 {
				let a = A_SpawnProjectile("ImpactX", 0);
				a.bNODECAL = true;
				a.SetStateLabel("XDeath");
				// Blood is sapawned from +BLOODSPLATTER
			}
			Stop;
	}
}

class BulletX_Glow : BulletX_Base {
	Default {
		+DONTSPLASH;
		RenderStyle "Add";
		Scale 1.0 / 32.0;
	}

	States {
		Spawn:
			BGLO A 1 Bright;
			Loop;
		Death:
			BGLO A 1 Bright;
			BGLO A 1 Bright { Scale -= (0.25, 0.25) / 32.0; if (min(Scale.X, Scale.Y) < 0.0) { Destroy(); } }
			Wait;
	}
}

class BulletX_Trail : BulletX_Base {
	Default {
		+DONTSPLASH;
		RenderStyle "Add";
	}

	States {
		Spawn:
			NULL A 1 Bright;
			Loop;
		Death:
			NULL A 1 Bright;
			NULL A 1 Bright { Scale -= (0.25, 0.25); if (min(Scale.X, Scale.Y) < 0.0) { Destroy(); } }
			Wait;
	}
}

class BulletX_Trail2 : BulletX_Base {
	Default {
		+DONTSPLASH;
		RenderStyle "Add";
		Scale 0;
	}
	
	States {
		Spawn:
			NULL A 1 NoDelay { if (min(Scale.X, Scale.Y) < 1.0) { Scale += (0.25, 0.25); } }
			Loop;
		Death:
			NULL A 1 Bright;
			NULL A 1 { Scale -= (0.25, 0.25); if (min(Scale.X, Scale.Y) < 0.0) { Destroy(); } }
			Wait;
	}
}