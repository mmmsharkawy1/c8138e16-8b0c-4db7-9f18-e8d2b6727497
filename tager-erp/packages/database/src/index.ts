import { createClient, SupabaseClient } from '@supabase/supabase-js';

export const createDatabaseClient = (url: string, key: string): SupabaseClient => {
    return createClient(url, key);
};

// Helper to get current tenant ID from JWT (if available)
export const getCurrentTenantId = async (supabase: SupabaseClient): Promise<string | null> => {
    const { data: { user } } = await supabase.auth.getUser();
    return user?.app_metadata?.tenant_id || null;
};
