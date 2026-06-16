# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Searches", type: :request do
  let(:category) { Category.create!(name: "Platforms") }
  let!(:target1) { Target.create!(category: category, name: "Lever", domain: "lever.co") }
  let!(:target2) { Target.create!(category: category, name: "Greenhouse", domain: "greenhouse.io") }

  let!(:search) do
    Search.create!(
      title: "Ruby Backend",
      query_conditions: "ruby",
      time_frame: "week",
      status: "pending"
    )
  end

  before do
    allow_any_instance_of(Search).to receive(:calculate_counters).and_return(
      { "all_clean" => 0, "interesting" => 0, "watched" => 0, "garbage" => 0 }.with_indifferent_access
    )
  end

  describe "GET /searches (index)" do
    it "returns a successful response and lists searches" do
      get searches_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ruby Backend")
    end
  end

  describe "GET /searches/:id (show)" do
    context "without filters" do
      it "returns a successful response and shows search details" do
        get search_path(search)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Ruby Backend")
      end
    end

    context "with filters applied" do
      it "successfully filters by status and time frame parameters" do
        allow_any_instance_of(Search).to receive(:calculate_counters).and_return(
          { "all_clean" => 1, "interesting" => 1, "watched" => 0, "garbage" => 0 }.with_indifferent_access
        )

        search.results.create!(
          title: "Senior Dev",
          url: "https://lever.co/1",
          url_hash: "abc123hash",
          status: "interesting"
        )

        get search_path(search), params: { status: "interesting", d: "day" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Senior Dev")
      end
    end
  end

  describe "GET /searches/new (new)" do
    it "returns a successful response" do
      get new_search_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /searches (create)" do
    context "with valid parameters" do
      let(:valid_params) do
        {
          search: {
            title: "Elixir Developer",
            query_conditions: "elixir OR phoenix",
            time_frame: "month",
            target_ids: [target1.id, target2.id]
          }
        }
      end

      it "creates a new Search and redirects to its show page" do
        expect do
          post searches_path, params: valid_params
        end.to change(Search, :count).by(1)

        created_search = Search.last
        expect(created_search.time_frame).to eq("month")
        expect(response).to redirect_to(search_path(created_search))

        follow_redirect!
        expect(response.body).to include("Search criteria was successfully created.")
      end
    end

    context "with invalid parameters" do
      let(:invalid_params) do
        {
          search: {
            title: "",
            query_conditions: "",
            time_frame: "invalid_frame"
          }
        }
      end

      it "does not create a search and returns unprocessable content" do
        expect do
          post searches_path, params: invalid_params
        end.not_to change(Search, :count)

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "POST /searches/:id/activate (activate)" do
    context "with Turbo Stream format (Asynchronous Pipeline)" do
      context "when target_ids are present" do
        before do
          allow_any_instance_of(Search).to receive(:activate_search!).and_return(true)
        end

        it "returns a turbo stream replacing the pipeline status badge" do
          post activate_search_path(search),
               params: { target_ids: [target1.id] },
               as: :turbo_stream

          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
          expect(response.body).to include(%(turbo-stream action="update" target="search_lifecycle_status"))
        end
      end
    end

    context "with Standard HTML format (Fallback)" do
      context "when target_ids are provided and activation succeeds" do
        before do
          allow_any_instance_of(Search).to receive(:activate_search!).and_return(true)
        end

        it "initializes the pipeline and redirects with a success notice" do
          post activate_search_path(search), params: { target_ids: [target1.id, target2.id] }

          expect(response).to redirect_to(search_path(search))

          follow_redirect!
          expect(response.body).to include("Scraping pipeline successfully initialized!")
        end
      end

      context "and activation service fails" do
        before do
          allow_any_instance_of(Search).to receive(:activate_search!).and_return(false)
        end

        it "redirects to show page with an alert message" do
          post activate_search_path(search), params: { target_ids: [target1.id] }

          expect(response).to redirect_to(search_path(search))

          follow_redirect!
          expect(response.body).to include("Failed to activate search. Check system logs.")
        end
      end
    end

    context "when target_ids are missing or empty" do
      it "redirects to show page with an alert warning to select targets" do
        post activate_search_path(search), params: { target_ids: nil }

        expect(response).to redirect_to(search_path(search))

        follow_redirect!
        expect(response.body).to include("Please select at least one target website to scrape.")
      end
    end
  end

  describe "DELETE /searches/:id (destroy)" do
    it "destroys the search and redirects to index" do
      expect do
        delete search_path(search)
      end.to change(Search, :count).by(-1)

      expect(response).to redirect_to(searches_path)

      follow_redirect!
      expect(response.body).to include("Search and all its results were successfully deleted.")
    end
  end
end
