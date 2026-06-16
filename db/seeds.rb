# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

sites_data = [
  {
    category_name: "ATS Platforms",
    items: [
      { name: "Greenhouse", domain: "boards.greenhouse.io" },
      { name: "Lever", domain: "jobs.lever.co" },
      { name: "Workday", domain: "myworkdayjobs.com" },
      { name: "Ashby", domain: "jobs.ashbyhq.com" },
      { name: "Rippling", domain: "ats.rippling.com" },
      { name: "JazzHR", domain: "app.jazz.co" },
      { name: "Personio", domain: "personio.de" },
      { name: "Recruitee", domain: "recruitee.com" },
      { name: "SmartRecruiters", domain: "jobs.smartrecruiters.com" },
      { name: "Taleo", domain: "taleo.net" },
      { name: "iCIMS", domain: "icims.com" },
      { name: "Jobvite", domain: "jobs.jobvite.com" },
      { name: "Breezy HR", domain: "breezy.hr" },
      { name: "Teamtailor", domain: "career.teamtailor.com" }, # Відомі хлопці :)
      { name: "Pinpoint", domain: "pinpointhq.com" },
      { name: "Workable", domain: "apply.workable.com" },
      { name: "Comeet", domain: "www.comeet.com" }
    ]
  },
  {
    category_name: "Job Boards",
    items: [
      { name: "LinkedIn", domain: "linkedin.com/jobs" },
      { name: "Indeed", domain: "indeed.com" },
      { name: "Glassdoor", domain: "glassdoor.com" },
      { name: "Wellfound", domain: "wellfound.com" },
      { name: "Y Combinator", domain: "workatastartup.com" },
      { name: "Remotive", domain: "remotive.io" },
      { name: "Remote OK", domain: "remoteok.com" },
      { name: "We Work Remotely", domain: "weworkremotely.com" },
      { name: "Himalayas", domain: "himalayas.app" },
      { name: "Djinni", domain: "djinni.co" },
      { name: "DOU", domain: "jobs.dou.ua" },
      { name: "EuroTech Jobs", domain: "eurotechjobs.com" },
      { name: "Relocate.me", domain: "relocate.me" },
      { name: "Otta", domain: "app.welcometothejungle.com/jobs" },
      { name: "HN Hiring", domain: "news.ycombinator.com" },
      { name: "Reddit Jobs", domain: "reddit.com/r/forhire" },
      { name: "Stack Overflow", domain: "stackoverflow.com/jobs" },
      { name: "Dice", domain: "dice.com" },
      { name: "SimplyHired", domain: "simplyhired.com" },
      { name: "Monster", domain: "monster.com" },
      { name: "Jobicy", domain: "jobicy.com" },
      { name: "NoDesk", domain: "nodesk.co" },
      { name: "4 day week", domain: "4dayweek.io" },
      { name: "Swissdevjobs", domain: "swissdevjobs.ch" },
      { name: "Just Remote", domain: "justremote.co" },
      { name: "Jobspresso", domain: "jobspresso.co" },
      { name: "Working Nomads", domain: "workingnomads.com" },
      { name: "Crypto Jobs List", domain: "cryptojobslist.com" },
      { name: "web3.career", domain: "web3.career" }
    ]
  }
]

Rails.logger.debug "Seeding categories and targets..."

sites_data.each do |group|
  category = Category.find_or_create_by!(name: group[:category_name])

  group[:items].each do |item|
    target = Target.find_or_initialize_by(domain: item[:domain])
    target.assign_attributes(
      name: item[:name],
      category: category,
      is_active: true
    )

    next unless target.changed?

    target.save!
    Rails.logger.debug do
      "  - [#{category.name}] #{target.persisted? ? 'Updated' : 'Created'} #{target.name} (#{target.domain})"
    end
  end
end

Rails.logger.debug "Seeding finished successfully!"
