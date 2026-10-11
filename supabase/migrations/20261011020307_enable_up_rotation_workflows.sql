-- Separate commit permits the terminal state in following function definitions.
ALTER TYPE public.iq_customer_wait_status ADD VALUE IF NOT EXISTS 'completed';
