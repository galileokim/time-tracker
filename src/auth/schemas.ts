import { z } from "zod";

const usernameSchema = z.string().trim().min(3).max(50).regex(/^[a-zA-Z0-9_.-]+$/);
const displayNameSchema = z.string().trim().min(1).max(100);
const emailSchema = z.email().trim().max(255).transform((email) => email.toLowerCase());
const passwordSchema = z.string().min(1).max(128);

export const registerSchema = z.object({
  username: usernameSchema,
  displayName: displayNameSchema,
  email: emailSchema,
  password: passwordSchema,
});

export const loginSchema = z.object({
  username: usernameSchema,
  password: z.string().min(1).max(128),
});

export type RegisterInput = z.infer<typeof registerSchema>;
export type LoginInput = z.infer<typeof loginSchema>;

export interface PublicUser {
  id: string;
  username: string;
  displayName: string;
  email: string;
  avatarUrl: string | null;
  createdAt: Date;
}

export interface AuthTokens {
  accessToken: string;
  tokenType: "Bearer";
  expiresInSeconds: number;
}
