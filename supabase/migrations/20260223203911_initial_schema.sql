-- 1. Create Enums
CREATE TYPE subscription_tier AS ENUM ('free', 'pro', 'enterprise');
CREATE TYPE subscription_status AS ENUM ('active', 'past_due', 'canceled');
CREATE TYPE integration_provider AS ENUM ('elevenlabs', 'openai', 'custom');

-- 2. Core Identity (Users)
CREATE TABLE public.users_profile (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    display_name TEXT,
    avatar_url TEXT,
    tier subscription_tier DEFAULT 'free',
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Billing & Usage
CREATE TABLE public.subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users_profile(id) ON DELETE CASCADE NOT NULL,
    stripe_customer_id TEXT,
    stripe_subscription_id TEXT,
    status subscription_status DEFAULT 'active',
    current_period_end TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.usage_metrics (
    user_id UUID REFERENCES public.users_profile(id) ON DELETE CASCADE PRIMARY KEY,
    storage_used_bytes BIGINT DEFAULT 0,
    last_calculated_at TIMESTAMPTZ DEFAULT now()
);

-- 4. The Agent Fleet
CREATE TABLE public.agents (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    owner_id UUID REFERENCES public.users_profile(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    gateway_url TEXT NOT NULL, -- e.g., ws://localhost:18789
    gateway_token_encrypted TEXT, -- BYOK for their local machine
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Character Mapping (SillyTavern style identity)
CREATE TABLE public.character_profiles (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    agent_id UUID REFERENCES public.agents(id) ON DELETE CASCADE NOT NULL,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    greeting_message TEXT,
    system_prompt_override TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. The Visual Canvas
CREATE TABLE public.themes (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    agent_id UUID REFERENCES public.agents(id) ON DELETE CASCADE NOT NULL,
    name TEXT NOT NULL,
    is_active BOOLEAN DEFAULT false,
    config JSONB DEFAULT '{}'::jsonb, -- CSS Vars, glass opacity, etc
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.environments (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    theme_id UUID REFERENCES public.themes(id) ON DELETE CASCADE NOT NULL,
    room_key TEXT NOT NULL,
    background_image_url TEXT,
    ambient_sound_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.sprites (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    agent_id UUID REFERENCES public.agents(id) ON DELETE CASCADE NOT NULL,
    emotion_key TEXT NOT NULL,
    sprite_url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. UI Extensions & Integrations
CREATE TABLE public.ui_extensions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    theme_id UUID REFERENCES public.themes(id) ON DELETE CASCADE NOT NULL,
    extension_key TEXT NOT NULL, -- e.g., 'spotify_widget'
    is_enabled BOOLEAN DEFAULT true,
    config JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.user_integrations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users_profile(id) ON DELETE CASCADE NOT NULL,
    provider integration_provider NOT NULL,
    api_key_encrypted TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- 8. Enable Row Level Security (RLS)
ALTER TABLE public.users_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.character_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.themes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.environments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sprites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ui_extensions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_integrations ENABLE ROW LEVEL SECURITY;

-- 9. Basic RLS Policies (Users can only select/insert/update their own data)
CREATE POLICY "Users can manage their own profile" ON public.users_profile FOR ALL USING (auth.uid() = id);
CREATE POLICY "Users can view their own agents" ON public.agents FOR ALL USING (auth.uid() = owner_id);
-- (Further strict RLS policies will be added as we build out the API)

-- 10. Auto-Create Profile Trigger
CREATE OR REPLACE FUNCTION public.handle_new_user() 
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users_profile (id, email, display_name)
  VALUES (new.id, new.email, new.raw_user_meta_data->>'full_name');
  
  INSERT INTO public.usage_metrics (user_id) VALUES (new.id);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();
