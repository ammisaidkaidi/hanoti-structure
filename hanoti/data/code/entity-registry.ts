import * as Auth from './entities/auth/index.js';
import * as Erp from './entities/erp/index.js';
import * as App from './entities/app/index.js';
import * as Settings from './entities/settings/index.js';

// One database and one DataSource; entity grouping is by SQL schema only.
export const authEntities = [
  Auth.User,
  Auth.Role,
  Auth.Permission,
  Auth.UserRole,
  Auth.RolePermission,
  Auth.Session,
  Auth.PasswordResetToken,
  Auth.EmailVerificationToken,
  Auth.PartyMembership,
  Auth.SubjectPermission,
] as const;
export const erpEntities = [
  Erp.Category,
  Erp.Brand,
  Erp.Product,
  Erp.Customer,
  Erp.Supplier,
  Erp.Warehouse,
  Erp.SalesOrder,
  Erp.SalesOrderItem,
  Erp.PurchaseOrder,
  Erp.PurchaseOrderItem,
  Erp.Payment,
  Erp.StockMovement,
] as const;
export const appEntities = [
  App.UserPreference,
  App.File,
  App.Notification,
  App.FeatureFlag,
  App.AuditEvent,
] as const;
export const settingsEntities = [
  Settings.SettingDefinition,
  Settings.GSettings,
  Settings.Setting,
] as const;
export const entitiesBySchema = {
  auth: authEntities,
  erp: erpEntities,
  app: appEntities,
  settings: settingsEntities,
} as const;
export const allEntities = [
  ...authEntities,
  ...erpEntities,
  ...appEntities,
  ...settingsEntities,
] as const;
