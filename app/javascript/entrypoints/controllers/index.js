import { application } from './application'

// Import controllers from the controllers directory
const controllers = import.meta.glob('../../../controllers/*_controller.js', { eager: true })

for (const path in controllers) {
  const controller = controllers[path]
  const name = path
    .split('/')
    .pop()
    .replace(/_controller\.js$/, '')
    .replace(/_/g, '-')
  
  application.register(name, controller.default)
}

