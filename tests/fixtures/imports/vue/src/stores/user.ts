import { defineStore } from 'pinia'
import type { User } from '~/types/user'
import { formatName } from '@/lib/format'

export const useUser = defineStore('user', () => {
  const name = formatName('  ada lovelace ')
  return { name } as User
})
