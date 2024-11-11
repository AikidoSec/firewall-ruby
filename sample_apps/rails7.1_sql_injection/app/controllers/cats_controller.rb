class CatsController < ApplicationController
  before_action :set_cat, only: %i[show edit update destroy]
  skip_forgery_protection if: -> { request.format.json? }

  # GET /cats
  def index
    @cats = Cat.all

    respond_to do |format|
      format.html
      format.json { render json: @cats }
    end
  end

  # GET /cats/1
  def show
    respond_to do |format|
      format.html
      format.json { render json: @cat }
    end
  end

  # GET /cats/new
  def new
    @cat = Cat.new
  end

  # GET /cats/1/edit
  def edit
  end

  # POST /cats
  def create
    @cat = Cat.new(cat_params)

    respond_to do |format|
      if @cat.save
        format.html { redirect_to @cat, notice: "Cat was created." }
        format.json { render json: @cat, status: :created, location: @cat }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: {errors: @cat.errors} }
      end
    end
  end

  # PATCH/PUT /cats/1
  def update
    respond_to do |format|
      if @cat.update(cat_params)
        format.html { redirect_to @cat, notice: "Cat was updated.", status: :see_other }
        format.json { render json: @cat, status: :ok }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: {errors: @cat.errors} }
      end
    end
  end

  # DELETE /cats/1
  def destroy
    @cat.destroy!

    respond_to do |format|
      format.html { redirect_to cats_url, notice: "Cat was destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private

  def set_cat
    # NOTE: This is insecure by design as a means to demonstrate a
    # vulnerability. Do not copy it or write code like this in your
    # applications.
    @cat = Cat.where("id = '#{params[:id]}'").first
  end

  def cat_params
    params.require(:cat).permit(:name)
  end
end
