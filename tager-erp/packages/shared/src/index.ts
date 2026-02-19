export const APP_NAME = "TAGER ERP";
export const VERSION = "1.0.0";

// Types
export type UserRole = 'owner' | 'admin' | 'manager' | 'cashier';

export interface Tenant {
    id: string;
    name: string;
    subdomain: string;
    settings: Record<string, any>;
    is_active: boolean;
}

// You can add more shared types here as the project grows
