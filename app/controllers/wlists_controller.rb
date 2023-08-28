class WlistsController < ApplicationController
  before_action :set_wlist, only: %i[ show edit update destroy ]

  # GET /wlists or /wlists.json
  def index
    @wlists = Wlist.all
  end

  # GET /wlists/1 or /wlists/1.json
  def show
  end

  # GET /wlists/new
  def new
    @wlist = Wlist.new
  end

  # GET /wlists/1/edit
  def edit
  end

  # POST /wlists or /wlists.json
  def create
    @wlist = Wlist.new(wlist_params)

    respond_to do |format|
      if @wlist.save
        format.html { redirect_to wlist_url(@wlist), notice: "Wlist was successfully created." }
        format.json { render :show, status: :created, location: @wlist }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @wlist.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /wlists/1 or /wlists/1.json
  def update
    respond_to do |format|
      if @wlist.update(wlist_params)
        format.html { redirect_to wlist_url(@wlist), notice: "Wlist was successfully updated." }
        format.json { render :show, status: :ok, location: @wlist }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @wlist.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /wlists/1 or /wlists/1.json
  def destroy
    @wlist.destroy

    respond_to do |format|
      format.html { redirect_to wlists_url, notice: "Wlist was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_wlist
      @wlist = Wlist.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def wlist_params
      params.require(:wlist).permit(:title, :user_id, :wl_category)
    end
end
