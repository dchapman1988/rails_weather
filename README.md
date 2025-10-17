# Weather Forecast Application

A Ruby on Rails weather forecast application using OpenWeather API with 30-minute caching by zip code.

## Setup

1. **Install dependencies**
   ```bash
   bundle install
   npm install
   ```

2. **Create `.env` file with API key**
   ```bash
   echo "OPENWEATHER_API_KEY=your_api_key_here" > .env
   ```

3. **Setup database**
   ```bash
   bin/rails db:create db:migrate
   RAILS_ENV=test bin/rails db:create db:migrate
   ```

4. **Run tests**
   ```bash
   bundle exec rspec
   ```

5. **Start server**
   ```bash
   bin/dev
   ```

   Visit http://localhost:3000


## Documentation

This project uses yard, to view run the following:

```bash
bundle exec yard
open doc/index.html
```
