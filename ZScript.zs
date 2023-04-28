version "4.0.0"

// Adapted from the Bullet-Z resource mod
// Since there is no way to catch every LineAttack call, we gotta make do. :/
// Can't reliably determine hitscan damage without WorldThingDamaged, but that doesn't tell for missed attacks. For now, it uses a user configurable damage.
// This will break hitscans with non standard damage.
// This must be loaded last.
// All puffs and blood are also replaced with my ImpactX mod.

class BulletX_Puff_Base : Actor {
	string from;
	Default {
		+NOINTERACTION;
		+NODECAL;
		+PUFFONACTORS;
		+ALWAYSPUFF;
		+PUFFGETSOWNER;
		+NOBLOOD;
		+BLOODLESSIMPACT;
		+SKYEXPLODE;
		+NOTIMEFREEZE;
		+HITTRACER;
		-BLOODSPLATTER;
		-RANDOMIZE;
		BounceType "Doom";
		VSpeed 0;
		DamageType "DummyDamage";
	}
	States {
		Spawn:
			TNT1 A 0 NoDelay { from = "Spawn"; } // Normal
			Goto Spawned;
		Melee:
			TNT1 A 0 { from = "Melee"; } // Punch
			Goto Spawned;
		Death:
			TNT1 A 0 { from = "Death"; } // Spawned Dead?
			Goto Spawned;
		XDeath:
			TNT1 A 0 { from = "XDeath"; } // Hit Bleeding Actor
			Goto Spawned;

		Spawned:
			TNT1 A 4 {
				if (target != null) {
					int damage = CVar.GetCVar("bx_damage").GetInt() * (CVar.GetCVar("bx_randomdamage") ? Random[GunShot](1, 3) : 1);
					if (target.bMISSILE && Distance2D(target) <= 1) { return; } // A_Tracer Fix
					float attackzoffset = target.height / 2.0;
					PlayerPawn player = PlayerPawn(target);
					if (player != null) {
						attackzoffset += player.AttackZOffset;
					}
					double distance = max(Distance2D(target), abs(pos.z - (target.pos.z + attackzoffset)));
					double meleerange = (target.Radius / 2.0) + target.MeleeRange + 22;
					pitch = VectorAngle(max(abs(pos.x - target.pos.x), abs(pos.y - target.pos.y)), -(pos.z - (target.pos.z + attackzoffset)));
					angle = VectorAngle(pos.x - target.pos.x, pos.y - target.pos.y);
					double angleOffset = (angle - target.angle);
					double pitchOffset = (pitch - target.pitch);
					if (from == "Melee" || distance < meleerange) { // Fix melee
						bool berserk = target.FindInventory("PowerStrength", true);
						target.A_CustomBulletAttack(angleOffset, pitchOffset, 1, damage * (from == "Melee"  && berserk ? 10 : 1), "ImpactX", (from == "Melee" ? distance : meleerange), CBAF_AIMFACING|CBAF_EXPLICITANGLE|CBAF_NORANDOMPUFFZ);
					}
					else {
						SetOrigin((Pos.x, Pos.y, Pos.z - 16), false); // Fix Offset
						Actor oldtargettarget = target.target;
						target.target = self;
						let bullet = BulletX_Bullet(target.A_SpawnProjectile("BulletX_Bullet"));
						bullet.SetDamage(damage);
						bullet.pitch = pitch;
						if (CVar.FindCVar("bx_tracerrounds").GetBool()) {
							bullet.glow = target.A_SpawnProjectile("BulletX_Glow");
							bullet.glow.pitch = pitch;
							bullet.trail = target.A_SpawnProjectile("BulletX_Trail");
							bullet.trail.pitch = pitch;
						}
						if (CVar.FindCVar("bx_vaportrails").GetBool()) {
							bullet.trail2 = target.A_SpawnProjectile("BulletX_Trail2");
							bullet.trail2.pitch = pitch;
						}
						target.target = oldtargettarget;
					}
				}
			}
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

	override void PostBeginPlay() {
		Super.PostBeginPlay();
		int speed = Max(32, CVar.FindCVar("bx_speed").GetInt());
		A_ScaleVelocity(speed);
	}
}

class BulletX_Bullet : BulletX_Base {
	Actor glow;
	Actor trail;
	Actor trail2;

	override void OnDestroy() {
		if (glow != null) {
			glow.Vel = (0,0,0);
			glow.SetStateLabel("Death");
		}
		if (trail != null) {
			trail.Vel = (0,0,0);
			trail.SetStateLabel("Death");
		}
		if (trail2 != null) {
			trail2.Vel = (0,0,0);
			trail2.SetStateLabel("Death");
		}
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
			BGLO A 1 Bright { Scale -= (0.25, 0.25) / 32.0; if (min(Scale.X, Scale.Y) < 0.0) { Destroy(); } }
			Loop;
	}
}

class BulletX_Trail : BulletX_Base {
	Default {
		+DONTSPLASH;
		RenderStyle "Add";
	}

	States {
		Spawn:
			PUFF A 1 Bright;
			Loop;
		Death:
			PUFF A 1 Bright;
			Stop;
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
			PUFF C 1 NoDelay { if (min(Scale.X, Scale.Y) < 1.0) { Scale += (0.25, 0.25); } }
			Loop;
		Death:
			PUFF C 1 { Scale -= (0.25, 0.25); if (min(Scale.X, Scale.Y) < 0.0) { Destroy(); } }
			Loop;
	}
}