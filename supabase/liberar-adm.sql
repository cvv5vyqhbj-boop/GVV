BEGIN;
ALTER TABLE public.profiles DISABLE TRIGGER trg_guard_profile_self_update;

UPDATE public.profiles
   SET role = 'super_admin', active = true, name = 'Alyson (ADM)'
 WHERE lower(email) = lower('alyson.hc@hotmail.com');

ALTER TABLE public.profiles ENABLE TRIGGER trg_guard_profile_self_update;
COMMIT;

SELECT email, role, active FROM public.profiles;
